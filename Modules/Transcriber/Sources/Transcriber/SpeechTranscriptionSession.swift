import AudioCapture
import AVFoundation
import CoreMedia
import Foundation
import Speech

/// 一路音频对应的流式转写会话。
///
/// 可以同时挂多种语言的识别器（例如中英双语会议）：每路候选各自出结果，
/// 用 final 结果的置信度判断「这段音频更像哪种语言」，把胜出的文本发出去。
/// 实时草稿只显示当前语言的那一份，避免两种语言的 partial 来回跳。
public actor SpeechTranscriptionSession {
    public let channel: AudioChannel

    private var analyzer: SpeechAnalyzer?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var analysisTask: Task<Void, Error>?
    private var resultsTasks: [Task<Void, Never>] = []
    private var eventContinuation: AsyncStream<TranscriptionEvent>.Continuation?
    private var converter: AudioFormatConverter?
    private var converterFormat: AVAudioFormat?
    private var analyzerFormat: AVAudioFormat?
    private var bufferCount = 0
    private var convertedFrames: AVAudioFrameCount = 0
    private var conversionFailures = 0
    private var resultCount = 0

    private var tracker = TranscriptionLanguageTracker()
    private var endedResultStreams = 0
    private var expectedLanguageCount = 1

    /// 置信度不高的 final 先压一会儿：另一种语言往往晚 1–2 秒才出结果，
    /// 等它到了再二选一，避免先把「拼音式的英文」或「硬凑的中文」闪到屏幕上。
    private var heldFinal: TranscriptionCandidate?
    private var heldAt: Date?
    private var heldFinalTask: Task<Void, Never>?
    private var openUtterances = OpenUtteranceTracker()
    /// 只有多语言时才需要「等另一种语言的结果」；单语言直接出，别白白多等 2.5 秒。
    private var holdsWeakFinals = false

    public init(channel: AudioChannel) {
        self.channel = channel
    }

    public func start(localeIdentifier: String) async throws -> AsyncStream<TranscriptionEvent> {
        try await start(localeIdentifiers: [localeIdentifier])
    }

    /// 安装语言模型、准备分析器并返回事件流。传多个语言时会在其间自动判别。
    public func start(localeIdentifiers: [String]) async throws -> AsyncStream<TranscriptionEvent> {
        await finish()

        var languages: [String] = []
        var locales: [Locale] = []
        for identifier in localeIdentifiers where !identifier.isEmpty {
            let locale = try await SpeechAssetManager.ensureInstalled(localeIdentifier: identifier)
            languages.append(identifier)
            locales.append(locale)
        }
        guard !locales.isEmpty else {
            throw TranscriptionError.localeUnsupported(localeIdentifiers.joined(separator: ", "))
        }

        // 必须用 progressiveTranscription 预设：自定义的空 options 虽然能出结果，
        // 但要等 end-of-input 才一次性吐出，实时字幕就变成「说完整段才出现」。
        // 再补上 transcriptionConfidence，多语言时靠它判断该信谁。
        var preset = SpeechTranscriber.Preset.progressiveTranscription
        preset.attributeOptions.insert(.transcriptionConfidence)
        let transcribers = locales.map { SpeechTranscriber(locale: $0, preset: preset) }

        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: transcribers)
            ?? AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)
        else {
            throw TranscriptionError.audioFormatUnavailable
        }

        let analyzer = SpeechAnalyzer(modules: transcribers)
        try await analyzer.prepareToAnalyze(in: format)

        let (events, eventContinuation) = AsyncStream<TranscriptionEvent>.makeStream()
        let (inputs, inputContinuation) = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .unbounded)

        self.analyzer = analyzer
        self.analyzerFormat = format
        self.converter = nil
        self.converterFormat = nil
        self.bufferCount = 0
        self.convertedFrames = 0
        self.conversionFailures = 0
        self.resultCount = 0
        self.endedResultStreams = 0
        self.expectedLanguageCount = max(1, languages.count)
        // 单语言不必猜，直接开草稿；多语言先闭嘴，等第一句 final 定下语言。
        self.tracker = TranscriptionLanguageTracker(
            initialLanguage: languages.count == 1 ? languages.first : nil
        )
        self.heldFinal = nil
        self.heldAt = nil
        self.holdsWeakFinals = languages.count > 1
        self.heldFinalTask?.cancel()
        self.heldFinalTask = nil
        self.openUtterances = OpenUtteranceTracker()
        self.eventContinuation = eventContinuation
        self.inputContinuation = inputContinuation

        TranscriptionLog.write(
            "[\(channel.rawValue)] start locales=\(languages.joined(separator: ",")) analyzerFormat=\(format)"
        )

        let channelName = channel.rawValue
        for (language, transcriber) in zip(languages, transcribers) {
            let task = Task { [weak self] in
                do {
                    for try await result in transcriber.results {
                        guard let self else { return }
                        await self.handle(result, language: language)
                    }
                } catch {
                    // 结果流异常结束时不阻塞上层；会话会通过 finish 收尾。
                    TranscriptionLog.write("[\(channelName)] results error (\(language)): \(error)")
                }
                TranscriptionLog.write("[\(channelName)] results stream ended (\(language))")
                await self?.noteResultsEnded()
            }
            resultsTasks.append(task)
        }

        // 不要继承会话 actor：分析器需要独立调度，否则在实时喂音频时结果会积压到结束才出来。
        analysisTask = Task {
            do {
                _ = try await analyzer.analyzeSequence(inputs)
            } catch {
                TranscriptionLog.write("[\(channelName)] analyze error: \(error)")
            }
        }

        return events
    }

    public func append(_ buffer: AVAudioPCMBuffer) {
        guard let inputContinuation, let analyzerFormat else { return }

        bufferCount += 1
        if bufferCount == 1 {
            TranscriptionLog.write(
                "[\(channel.rawValue)] first buffer format=\(buffer.format) frames=\(buffer.frameLength)"
            )
        }

        if Self.matches(buffer.format, analyzerFormat) {
            inputContinuation.yield(AnalyzerInput(buffer: buffer))
            logProgressIfNeeded()
            return
        }

        // 输入格式偶尔会变（例如切换设备），变了就重建转换器。
        if converter == nil || !Self.matches(converterFormat ?? buffer.format, buffer.format) {
            converter = AudioFormatConverter(from: buffer.format, to: analyzerFormat)
            converterFormat = buffer.format
        }
        do {
            guard let converter else { return }
            let converted = try converter.convert(buffer)
            convertedFrames += converted.frameLength
            inputContinuation.yield(AnalyzerInput(buffer: converted))
        } catch {
            conversionFailures += 1
            if conversionFailures <= 3 {
                TranscriptionLog.write("[\(channel.rawValue)] convert failed: \(error)")
            }
        }
        logProgressIfNeeded()
    }

    private func logProgressIfNeeded() {
        guard bufferCount % 200 == 0 else { return }
        TranscriptionLog.write(
            "[\(channel.rawValue)] buffers=\(bufferCount) outFrames=\(convertedFrames) convertFailures=\(conversionFailures) results=\(resultCount)"
        )
    }

    public func finish() async {
        if bufferCount > 0 {
            TranscriptionLog.write(
                "[\(channel.rawValue)] finish buffers=\(bufferCount) outFrames=\(convertedFrames) failures=\(conversionFailures) results=\(resultCount)"
            )
        }
        inputContinuation?.finish()
        inputContinuation = nil

        if let analysisTask {
            _ = try? await analysisTask.value
        }
        analysisTask = nil

        if let analyzer {
            try? await analyzer.finalizeAndFinishThroughEndOfInput()
        }
        analyzer = nil

        await waitForResults()
        flushHeldFinal()
        converter = nil
        analyzerFormat = nil
        await closeEvents()
    }

    // MARK: - 结果合并

    private func handle(_ result: SpeechTranscriber.Result, language: String) {
        let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let candidate = TranscriptionCandidate(
            language: language,
            text: text,
            isFinal: result.isFinal,
            confidence: Self.confidence(of: result.text),
            rangeStart: result.range.start.seconds,
            rangeEnd: result.range.end.seconds
        )

        if candidate.isFinal {
            handleFinal(candidate)
        } else if tracker.acceptsPartial(language) {
            emit(candidate)
        }
        // 处理完再记：这条 final 本身要先拿来和压着的候选比，不能先把自己那路标成已定稿。
        openUtterances.note(candidate)
    }

    private func handleFinal(_ candidate: TranscriptionCandidate) {
        TranscriptionLog.write(
            "[\(channel.rawValue)] candidate lang=\(candidate.language) conf=\(String(format: "%.2f", candidate.confidence)) "
                + "range=\(String(format: "%.2f-%.2f", candidate.rangeStart, candidate.rangeEnd)) text=\(candidate.text.prefix(40))"
        )
        guard holdsWeakFinals else {
            accept(candidate)
            return
        }

        // 两种语言对同一句给出的时间区间可能差很远，用「到达时间」判断是不是同一句更稳。
        if let heldAt, let heldFinal, Date().timeIntervalSince(heldAt) > 3,
           !openUtterances.shouldKeepHolding(heldFinal, heldFor: Date().timeIntervalSince(heldAt)) {
            flushHeldFinal()
        }

        if candidate.confidence >= TranscriptionLanguageTracker.strongConfidence {
            // 高置信度直接采信，同一句里更弱的候选不必再等。
            dropHeldFinal()
            accept(candidate)
            return
        }

        if let heldFinal, heldFinal.confidence >= candidate.confidence {
            scheduleHeldFinalFlush()
            return
        }
        heldFinal = candidate
        heldAt = Date()
        scheduleHeldFinalFlush()
    }

    private func scheduleHeldFinalFlush() {
        heldFinalTask?.cancel()
        heldFinalTask = Task.detached { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            await self?.flushHeldFinalIfNeeded()
        }
    }

    private func flushHeldFinalIfNeeded() {
        guard let heldFinal, let heldAt else { return }
        // 另一种语言这句还没说完：再等等它的 final，别先把硬凑的结果放上屏。
        if openUtterances.shouldKeepHolding(heldFinal, heldFor: Date().timeIntervalSince(heldAt)) {
            scheduleHeldFinalFlush()
            return
        }
        flushHeldFinal()
    }

    private func flushHeldFinal() {
        heldFinalTask?.cancel()
        heldFinalTask = nil
        guard let candidate = heldFinal else { return }
        heldFinal = nil
        heldAt = nil
        accept(candidate)
    }

    private func dropHeldFinal() {
        heldFinalTask?.cancel()
        heldFinalTask = nil
        heldFinal = nil
        heldAt = nil
    }

    private func accept(_ candidate: TranscriptionCandidate) {
        guard tracker.acceptFinal(candidate) else { return }
        emit(candidate)
    }

    private func emit(_ candidate: TranscriptionCandidate) {
        resultCount += 1
        if candidate.isFinal || resultCount <= 3 {
            TranscriptionLog.write(
                "[\(channel.rawValue)] result lang=\(candidate.language) final=\(candidate.isFinal) "
                    + "conf=\(String(format: "%.2f", candidate.confidence)) chars=\(candidate.text.count) "
                    + "text=\(candidate.text.prefix(40))"
            )
        }
        eventContinuation?.yield(
            TranscriptionEvent(
                channel: channel,
                text: candidate.text,
                isFinal: candidate.isFinal,
                language: candidate.language
            )
        )
    }

    /// 每个 run 带一个置信度，取平均做语言判别的依据。
    private static func confidence(of text: AttributedString) -> Double {
        var sum = 0.0
        var count = 0
        for run in text.runs {
            if let value = run.transcriptionConfidence {
                sum += value
                count += 1
            }
        }
        guard count > 0 else { return 0 }
        return sum / Double(count)
    }

    private func noteResultsEnded() {
        endedResultStreams += 1
        guard endedResultStreams >= expectedLanguageCount else { return }
        flushHeldFinal()
        eventContinuation?.finish()
        eventContinuation = nil
    }

    private func waitForResults() async {
        let tasks = resultsTasks
        resultsTasks = []
        guard !tasks.isEmpty else { return }
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for task in tasks {
                    await task.value
                }
            }
            group.addTask { try? await Task.sleep(for: .seconds(5)) }
            await group.next()
            group.cancelAll()
        }
        tasks.forEach { $0.cancel() }
    }

    private func closeEvents() async {
        eventContinuation?.finish()
        eventContinuation = nil
    }

    private static func matches(_ lhs: AVAudioFormat, _ rhs: AVAudioFormat) -> Bool {
        lhs.sampleRate == rhs.sampleRate
            && lhs.channelCount == rhs.channelCount
            && lhs.commonFormat == rhs.commonFormat
            && lhs.isInterleaved == rhs.isInterleaved
    }
}
