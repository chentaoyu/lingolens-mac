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

/// 麦克风采集，开启 voice processing 以便外放时抑制回声。
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
        if !input.isVoiceProcessingEnabled {
            try input.setVoiceProcessingEnabled(true)
        }

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
