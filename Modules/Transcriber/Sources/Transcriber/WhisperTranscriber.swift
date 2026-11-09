import AudioCapture
import AVFoundation
import Foundation

/// 转写边车输出的一段定稿文本。
public struct WhisperSegment: Sendable, Equatable {
    public let text: String
    public let start: Double
    public let end: Double

    public init(text: String, start: Double, end: Double) {
        self.text = text
        self.start = start
        self.end = end
    }
}

public enum WhisperSidecarEvent: Sendable, Equatable {
    /// 模型加载完成，可以开始灌音频。
    case ready
    case final(WhisperSegment)
    case failure(String)
}

/// 解析边车标准输出的一行 JSON。单独拆出来便于单元测试。
public enum WhisperEventParser {
    public static func parse(_ line: String) -> WhisperSidecarEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.hasPrefix("{") else { return nil }
        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String
        else { return nil }

        switch type {
        case "ready":
            return .ready
        case "final":
            guard let text = object["text"] as? String,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return nil }
            return .final(WhisperSegment(
                text: text,
                start: number(object["start"]),
                end: number(object["end"])
            ))
        case "error":
            return .failure(object["message"] as? String ?? "未知错误")
        default:
            return nil
        }
    }

    private static func number(_ value: Any?) -> Double {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let number = value as? NSNumber { return number.doubleValue }
        return 0
    }
}

/// 把 float32 PCM 转成边车要求的小端 int16。
public enum PCM16Encoder {
    public static func encode(_ buffer: AVAudioPCMBuffer) -> Data? {
        guard let channels = buffer.floatChannelData else { return nil }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return nil }

        var samples = [Int16](repeating: 0, count: frames)
        let source = channels[0]
        for frame in 0..<frames {
            let clamped = max(-1, min(1, source[frame]))
            samples[frame] = Int16(clamped * 32767)
        }
        return samples.withUnsafeBufferPointer { Data(buffer: $0) }
    }
}

public enum WhisperTranscriberError: Error, LocalizedError {
    case pythonMissing(String)
    case scriptMissing(String)
    case launchFailed(String)
    case notReady

    public var errorDescription: String? {
        switch self {
        case let .pythonMissing(path): return "找不到 Python 解释器：" + path
        case let .scriptMissing(path): return "找不到转写脚本：" + path
        case let .launchFailed(message): return "启动转写进程失败：" + message
        case .notReady: return "转写进程尚未就绪。"
        }
    }
}

/// 常驻的 Whisper 转写进程。
///
/// 音频统一转成 16 kHz 单声道 int16 后经标准输入灌进去，边车自己断句并输出 JSON 行。
/// 常驻而不是每句起一个进程：模型加载约 1.8 秒，逐句加载完全不可用。
public actor WhisperTranscriber {
    public let language: String
    public let hotwords: [String]

    private let modelDirectory: URL
    private let pythonExecutable: URL
    private let scriptURL: URL
    private var process: Process?
    private var stdinHandle: FileHandle?
    private var readerTask: Task<Void, Never>?
    private var eventContinuation: AsyncStream<WhisperSidecarEvent>.Continuation?
    private var readyContinuation: CheckedContinuation<Void, Error>?
    private var didSignalReady = false
    private var converter: AudioFormatConverter?
    private var converterFormat: AVAudioFormat?
    private var stderrTail = ""
    private var rawLineCount = 0
    private var stdoutHandler: FileHandle?
    private var stderrHandler: FileHandle?

    private static var targetFormat: AVAudioFormat? {
        AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)
    }

    public init(
        modelDirectory: URL,
        pythonExecutable: URL,
        scriptURL: URL,
        language: String = "zh",
        hotwords: [String] = []
    ) {
        self.modelDirectory = modelDirectory
        self.pythonExecutable = pythonExecutable
        self.scriptURL = scriptURL
        self.language = language
        self.hotwords = hotwords
    }

    /// 启动进程并等到 ready，返回只包含 final 与 failure 的事件流。
    public func start() async throws -> AsyncStream<WhisperSidecarEvent> {
        await stop()

        guard FileManager.default.isExecutableFile(atPath: pythonExecutable.path) else {
            throw WhisperTranscriberError.pythonMissing(pythonExecutable.path)
        }
        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            throw WhisperTranscriberError.scriptMissing(scriptURL.path)
        }

        let process = Process()
        process.executableURL = pythonExecutable
        var arguments = [scriptURL.path, "--model", modelDirectory.path, "--language", language]
        if !hotwords.isEmpty {
            arguments += ["--hotwords", hotwords.joined(separator: ",")]
        }
        process.arguments = arguments
        // 让 Python 不缓冲，否则事件会攒到进程结束才上来。
        process.environment = ProcessInfo.processInfo.environment.merging(
            ["PYTHONUNBUFFERED": "1"]
        ) { _, new in new }

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let (events, continuation) = AsyncStream<WhisperSidecarEvent>.makeStream()
        self.eventContinuation = continuation
        self.didSignalReady = false

        do {
            try process.run()
        } catch {
            self.eventContinuation = nil
            throw WhisperTranscriberError.launchFailed(error.localizedDescription)
        }

        self.process = process
        self.stdinHandle = inputPipe.fileHandleForWriting

        rawLineCount = 0
        stderrTail = ""
        attachReaders(
            stdout: outputPipe.fileHandleForReading,
            stderr: errorPipe.fileHandleForReading
        )

        TranscriptionLog.write(
            "[whisper] 已启动进程 pid=\(process.processIdentifier) model=\(modelDirectory.lastPathComponent)"
        )

        // 模型加载 1–2 秒，给足超时；超时说明进程起不来。
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in
                guard let self else { return }
                try await self.awaitReady()
            }
            group.addTask {
                try await Task.sleep(for: .seconds(60))
                throw WhisperTranscriberError.launchFailed("等待转写进程就绪超时")
            }
            try await group.next()
            group.cancelAll()
        }

        return events
    }

    /// 灌入一块采集音频；内部转成 16 kHz 单声道 int16。失败静默丢弃，不打断会话。
    public func append(_ buffer: AVAudioPCMBuffer) {
        guard let stdinHandle, let target = Self.targetFormat else { return }
        do {
            let converted = try convert(buffer, to: target)
            guard let data = PCM16Encoder.encode(converted) else { return }
            try stdinHandle.write(contentsOf: data)
        } catch {
            // 进程已经退出等情况：忽略，由事件流报告。
        }
    }

    /// 关掉标准输入，等边车把最后一段转写完退出。
    public func finish() async {
        try? stdinHandle?.close()
        stdinHandle = nil
        if let process, process.isRunning {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                process.terminationHandler = { _ in continuation.resume() }
                DispatchQueue.global().asyncAfter(deadline: .now() + 120) {
                    if process.isRunning { process.terminate() }
                }
            }
        }
        await stop()
    }

    public func stop() async {
        stdoutHandler?.readabilityHandler = nil
        stderrHandler?.readabilityHandler = nil
        stdoutHandler = nil
        stderrHandler = nil
        readerTask?.cancel()
        readerTask = nil
        if let process, process.isRunning {
            process.terminate()
        }
        process = nil
        try? stdinHandle?.close()
        stdinHandle = nil
        converter = nil
        converterFormat = nil
        eventContinuation?.finish()
        eventContinuation = nil
        didSignalReady = false
        if let readyContinuation {
            self.readyContinuation = nil
            readyContinuation.resume(throwing: WhisperTranscriberError.notReady)
        }
    }

    /// 最近一次失败时的标准错误尾巴，便于定位。
    public func diagnosticOutput() -> String {
        stderrTail
    }

    // MARK: - 私有

    private func convert(_ buffer: AVAudioPCMBuffer, to target: AVAudioFormat) throws -> AVAudioPCMBuffer {
        if Self.matches(buffer.format, target) {
            converter = nil
            converterFormat = buffer.format
            return buffer
        }
        if converter == nil || !Self.matches(converterFormat, buffer.format) {
            guard let newConverter = AudioFormatConverter(from: buffer.format, to: target) else {
                throw WhisperTranscriberError.launchFailed("不支持的音频格式")
            }
            converter = newConverter
            converterFormat = buffer.format
        }
        guard let converter else {
            throw WhisperTranscriberError.launchFailed("转换器创建失败")
        }
        return try converter.convert(buffer)
    }

    private func awaitReady() async throws {
        TranscriptionLog.write("[whisper] 等待 ready didSignalReady=\(didSignalReady)")
        if didSignalReady { return }
        try await withCheckedThrowingContinuation { continuation in
            readyContinuation = continuation
        }
        TranscriptionLog.write("[whisper] ready 等待结束")
    }

    /// 用 readabilityHandler 读管道，而不是 FileHandle.bytes。
    ///
    /// 实测同一个 App 里开第二条管道时，bytes 的异步序列收不到数据：
    /// 子进程明明已经打印了 ready（RSS 690MB，模型已加载），App 却一直等，
    /// 直到进程被杀、管道 EOF 才一次性拿到。readabilityHandler 由内核可读事件驱动，
    /// 多条管道互不影响（ProcessCommandRunner 早就用的这套）。
    private func attachReaders(stdout: FileHandle, stderr: FileHandle) {
        let outLines = LineSplitter { [weak self] line in
            Task { await self?.handleStdoutLine(line) }
        }
        let errLines = LineSplitter { [weak self] line in
            Task { await self?.appendStderr(line) }
        }
        stdout.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            outLines.consume(data)
        }
        stderr.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            errLines.consume(data)
        }
        stdoutHandler = stdout
        stderrHandler = stderr
    }

    private func handleStdoutLine(_ line: String) {
        if rawLineCount < 3 {
            rawLineCount += 1
            TranscriptionLog.write("[whisper-raw] 第\(rawLineCount)行: \(line.prefix(60))")
        }
        guard let event = WhisperEventParser.parse(line) else { return }
        offer(event)
    }

    private func appendStderr(_ line: String) {
        stderrTail += line + "\n"
        if stderrTail.count > 4000 {
            stderrTail = String(stderrTail.suffix(4000))
        }
    }

    private func offer(_ event: WhisperSidecarEvent) {
        if case .ready = event {
            TranscriptionLog.write("[whisper] 收到 ready")
            signalReady(.success(()))
            return
        }
        eventContinuation?.yield(event)
    }

    private func signalReady(_ result: Result<Void, Error>) {
        if case .success = result { didSignalReady = true }
        guard let continuation = readyContinuation else { return }
        readyContinuation = nil
        continuation.resume(with: result)
    }

    private static func matches(_ lhs: AVAudioFormat?, _ rhs: AVAudioFormat) -> Bool {
        guard let lhs else { return false }
        return lhs.sampleRate == rhs.sampleRate
            && lhs.channelCount == rhs.channelCount
            && lhs.commonFormat == rhs.commonFormat
            && lhs.isInterleaved == rhs.isInterleaved
    }
}
