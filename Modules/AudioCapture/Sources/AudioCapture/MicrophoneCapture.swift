import AVFoundation
import Foundation

public enum MicrophoneCaptureError: Error, LocalizedError {
    case permissionDenied
    case invalidFormat
    case engineStartFailed(String)

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "没有麦克风权限，请在系统设置中允许 LingoLens 使用麦克风。"
        case .invalidFormat:
            return "无法读取麦克风音频格式。"
        case let .engineStartFailed(message):
            return "麦克风启动失败：\(message)"
        }
    }
}

/// 麦克风采集。
///
/// 这里**故意不开启 voice processing**，因为 AUVoiceIO 会让两个功能不可用：
/// 1. 系统会把「其它音频」（Teams 里对方的声音）自动 duck 掉约 30 dB，用户听得的小时也调不回来；
/// 2. 同一进程里一旦有 voice processing，Core Audio 的进程 Tap 就收不到系统音频——
///    先建 Tap 再开 VP 时，Tap 会在约 0.4 秒后停止出数据，对方的字幕整段丢失。
/// 实测普通 AVAudioEngine 输入 + 进程 Tap 可以稳定共存，所以让回声消除让位给系统音频采集。
/// 代价是外放时对方的声音会从麦克风串进来，建议开会时戴耳机。
public final class MicrophoneCapture: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let onBuffer: @Sendable (AVAudioPCMBuffer) -> Void
    private var running = false

    public init(onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) {
        self.onBuffer = onBuffer
    }

    public static var authorizationStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    public static func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    public func start() throws {
        guard !running else { return }
        guard Self.authorizationStatus == .authorized else {
            throw MicrophoneCaptureError.permissionDenied
        }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw MicrophoneCaptureError.invalidFormat
        }

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self, let copy = AudioBufferTools.copy(buffer) else { return }
            self.onBuffer(copy)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw MicrophoneCaptureError.engineStartFailed(error.localizedDescription)
        }
        running = true
    }

    public func stop() {
        guard running else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        running = false
    }
}
