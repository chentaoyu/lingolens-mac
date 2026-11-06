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
    private var analyzerFormat: AVAudioFormat?
    private var lastText: String = ""

    public init(channel: AudioChannel) {
        self.channel = channel
    }

    /// 安装语音模型、准备分析器并返回事件流。
    public func start(localeIdentifier: String) async throws -> AsyncStream<TranscriptionEvent> {
        await finish()

        let locale = try await SpeechAssetManager.ensureInstalled(localeIdentifier: localeIdentifier)
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )

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
        self.eventContinuation = eventContinuation
        self.inputContinuation = inputContinuation
        self.lastText = ""

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
            }
            await self?.closeEvents()
        }

        analysisTask = Task {
            try await analyzer.analyzeSequence(inputs)
        }

        return events
    }

    public func append(_ buffer: AVAudioPCMBuffer) {
        guard let inputContinuation, let analyzerFormat else { return }

        if Self.matches(buffer.format, analyzerFormat) {
            inputContinuation.yield(AnalyzerInput(buffer: buffer))
            return
        }

        if converter == nil {
            converter = AudioFormatConverter(from: buffer.format, to: analyzerFormat)
        }
        guard let converter, let converted = try? converter.convert(buffer) else { return }
        inputContinuation.yield(AnalyzerInput(buffer: converted))
    }

    public func finish() async {
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
