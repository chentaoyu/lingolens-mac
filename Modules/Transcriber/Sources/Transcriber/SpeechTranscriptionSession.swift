import AudioCapture
import AVFoundation
import Foundation
import Speech

/// 一路音频对应的流式转写会话。
public actor SpeechTranscriptionSession {
    public let channel: AudioChannel

    private var analyzer: SpeechAnalyzer?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var analysisTask: Task<Void, Error>?
    private var resultsTask: Task<Void, Never>?
    private var eventContinuation: AsyncStream<TranscriptionEvent>.Continuation?
    private var converter: AudioFormatConverter?
    private var converterFormat: AVAudioFormat?
    private var analyzerFormat: AVAudioFormat?
    private var lastText: String = ""
    private var bufferCount = 0
    private var convertedFrames: AVAudioFrameCount = 0
    private var conversionFailures = 0
    private var resultCount = 0

    public init(channel: AudioChannel) {
        self.channel = channel
    }

    /// 安装语音模型、准备分析器并返回事件流。
    public func start(localeIdentifier: String) async throws -> AsyncStream<TranscriptionEvent> {
        await finish()

        let locale = try await SpeechAssetManager.ensureInstalled(localeIdentifier: localeIdentifier)
        // 必须用 progressiveTranscription 预设：自定义的空 options 虽然能出结果，
        // 但要等 end-of-input 才一次性吐出，实时字幕就变成「说完整段才出现」。
        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)

        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
            ?? AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)
        else {
            throw TranscriptionError.audioFormatUnavailable
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
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
        TranscriptionLog.write(
            "[\(channel.rawValue)] start locale=\(locale.identifier) analyzerFormat=\(format)"
        )
        self.eventContinuation = eventContinuation
        self.inputContinuation = inputContinuation
        self.lastText = ""

        let channelName = channel.rawValue
        resultsTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    guard let self else { break }
                    let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { continue }
                    let isFinal = result.isFinal
                    await self.emit(text: text, isFinal: isFinal)
                }
            } catch {
                // 结果流异常结束时不阻塞上层；会话会通过 finish 收尾。
                TranscriptionLog.write("[\(channelName)] results error: \(error)")
            }
            TranscriptionLog.write("[\(channelName)] results stream ended")
            await self?.closeEvents()
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
        converter = nil
        analyzerFormat = nil
        await closeEvents()
    }

    private func waitForResults() async {
        guard let resultsTask else { return }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await resultsTask.value }
            group.addTask { try? await Task.sleep(for: .seconds(5)) }
            await group.next()
            group.cancelAll()
        }
        resultsTask.cancel()
        self.resultsTask = nil
    }

    private func emit(text: String, isFinal: Bool) {
        lastText = text
        resultCount += 1
        if isFinal || resultCount <= 3 {
            TranscriptionLog.write(
                "[\(channel.rawValue)] result final=\(isFinal) chars=\(text.count) text=\(text.prefix(40))"
            )
        }
        eventContinuation?.yield(
            TranscriptionEvent(channel: channel, text: text, isFinal: isFinal)
        )
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
