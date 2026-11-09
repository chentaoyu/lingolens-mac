import AVFoundation
import Foundation

/// 把一路采集音频落盘成 m4a，供事后复盘、重转写与识别效果比对。
///
/// 统一录成 **16 kHz 单声道 AAC**：这正是语音识别实际使用的格式，
/// 既能直接喂给识别引擎做 A/B，也能控制体积（约 16 MB/小时）。
/// 写入放在私有串行队列上，不占用采集回调或主线程。
public final class ChannelAudioRecorder: @unchecked Sendable {
    /// 录音采样率，与识别器输入保持一致。
    public static let sampleRate: Double = 16_000
    /// AAC 码率（bit/s）。
    public static let bitRate = 32_000

    public let url: URL

    private let queue: DispatchQueue
    private var file: AVAudioFile?
    private var converter: AudioFormatConverter?
    private var sourceFormat: AVAudioFormat?
    private var finished = false
    /// 已写入帧数与失败次数，供结束后登记与排障。
    public private(set) var writtenFrames: AVAudioFrameCount = 0
    public private(set) var failureCount = 0

    private static var standardFormat: AVAudioFormat? {
        AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
    }

    /// - Throws: 目录不存在、格式不受支持或文件创建失败时抛出。
    public init(url: URL) throws {
        self.url = url
        let queue = DispatchQueue(label: "com.lingolens.recorder.\(url.lastPathComponent)")
        self.queue = queue

        guard let format = Self.standardFormat else {
            throw AudioRecorderError.unsupportedFormat
        }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: Self.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: Self.bitRate
        ]
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            self.file = try AVAudioFile(
                forWriting: url,
                settings: settings,
                commonFormat: format.commonFormat,
                interleaved: format.isInterleaved
            )
        } catch {
            throw AudioRecorderError.createFailed(error.localizedDescription)
        }
        // 采集格式由第一块缓冲区决定，这里先记下标准格式作为兜底。
        self.converter = nil
        self.sourceFormat = nil
    }

    /// 追加一块采集音频；内部按需转换采样率与声道。失败只计数，不打断采集。
    public func append(_ buffer: AVAudioPCMBuffer) {
        queue.async { [weak self] in
            self?.write(buffer)
        }
    }

    /// 阻塞到已入队的音频全部写完并关闭文件。
    public func finish() {
        queue.sync {
            finished = true
            file = nil
            converter = nil
        }
    }

    /// 已写入的时长（秒）。
    public var duration: TimeInterval {
        queue.sync {
            Double(writtenFrames) / Self.sampleRate
        }
    }

    // MARK: - 私有

    private func write(_ buffer: AVAudioPCMBuffer) {
        guard !finished, let file else { return }
        guard buffer.frameLength > 0 else { return }

        do {
            let converted = try convertIfNeeded(buffer)
            try file.write(from: converted)
            writtenFrames += converted.frameLength
        } catch {
            failureCount += 1
        }
    }

    private func convertIfNeeded(_ buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        guard let target = Self.standardFormat else {
            throw AudioRecorderError.unsupportedFormat
        }
        // 已经是目标格式就直接写：绕开转换器可以避免它每次调用的缓冲延迟丢帧。
        if Self.matches(buffer.format, target) {
            converter = nil
            sourceFormat = buffer.format
            return buffer
        }
        // 采集格式经常变（切换设备、切换输出），变了就重建转换器。
        if converter == nil || !Self.matches(sourceFormat, buffer.format) {
            guard let newConverter = AudioFormatConverter(from: buffer.format, to: target) else {
                throw AudioRecorderError.unsupportedFormat
            }
            converter = newConverter
            sourceFormat = buffer.format
        }
        guard let converter else {
            throw AudioRecorderError.unsupportedFormat
        }
        return try converter.convert(buffer)
    }

    private static func matches(_ lhs: AVAudioFormat?, _ rhs: AVAudioFormat) -> Bool {
        guard let lhs else { return false }
        return lhs.sampleRate == rhs.sampleRate
            && lhs.channelCount == rhs.channelCount
            && lhs.commonFormat == rhs.commonFormat
            && lhs.isInterleaved == rhs.isInterleaved
    }
}

public enum AudioRecorderError: Error, LocalizedError, Equatable {
    case unsupportedFormat
    case createFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat: return "录音格式不受支持。"
        case let .createFailed(message): return "创建录音文件失败：\(message)"
        }
    }
}
