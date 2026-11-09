import AVFoundation
import Foundation

public struct AudioCaptureOptions: Sendable, Equatable {
    public var captureSystemAudio: Bool
    public var captureMicrophone: Bool

    public init(captureSystemAudio: Bool = true, captureMicrophone: Bool = true) {
        self.captureSystemAudio = captureSystemAudio
        self.captureMicrophone = captureMicrophone
    }

    public static let both = AudioCaptureOptions(captureSystemAudio: true, captureMicrophone: true)
}

public enum AudioCaptureError: Error, LocalizedError {
    case noSourceEnabled
    case microphoneDenied
    case systemAudioFailed(String)
    case microphoneFailed(String)

    public var errorDescription: String? {
        switch self {
        case .noSourceEnabled: return "请至少选择一路音频来源。"
        case .microphoneDenied: return "没有麦克风权限。"
        case let .systemAudioFailed(message): return "系统音频采集失败：\(message)"
        case let .microphoneFailed(message): return "麦克风采集失败：\(message)"
        }
    }
}

/// 同时管理系统音频与麦克风两路采集，输出带通道标记的音频流。
public final class AudioCaptureController: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<TaggedAudioBuffer>.Continuation?
    private var systemTap: SystemAudioTap?
    private var microphone: MicrophoneCapture?
    private var stream: AsyncStream<TaggedAudioBuffer>?
    private(set) public var isRunning = false
    /// 某一路启动失败但另一路成功时的告警。
    public private(set) var warnings: [String] = []

    public init() {}

    public func start(options: AudioCaptureOptions = .both) throws -> AsyncStream<TaggedAudioBuffer> {
        stop()
        guard options.captureSystemAudio || options.captureMicrophone else {
            throw AudioCaptureError.noSourceEnabled
        }

        let (stream, continuation) = AsyncStream<TaggedAudioBuffer>.makeStream(bufferingPolicy: .bufferingNewest(64))
        lock.lock()
        self.stream = stream
        self.continuation = continuation
        lock.unlock()

        var startedSystem = false
        var startedMicrophone = false
        var errors: [String] = []

        if options.captureSystemAudio {
            let tap = SystemAudioTap { [weak self] buffer in
                self?.emit(channel: .other, buffer: buffer)
            }
            do {
                try tap.start()
                systemTap = tap
                startedSystem = true
            } catch {
                errors.append(error.localizedDescription)
            }
        }

        if options.captureMicrophone {
            let microphone = MicrophoneCapture { [weak self] buffer in
                self?.emit(channel: .me, buffer: buffer)
            }
            do {
                try microphone.start()
                self.microphone = microphone
                startedMicrophone = true
            } catch {
                errors.append(error.localizedDescription)
            }
        }

        if !startedSystem && !startedMicrophone {
            continuation.finish()
            self.continuation = nil
            self.stream = nil
            throw AudioCaptureError.systemAudioFailed(errors.joined(separator: "；"))
        }

        warnings = errors
        isRunning = true
        return stream
    }

    /// 会话进行中单独开关麦克风：跟随会议软件时，别的应用不开麦就不占用设备，
    /// 免得系统一直显示麦克风在用。
    public func setMicrophoneActive(_ active: Bool) throws {
        if active {
            guard microphone == nil else { return }
            let microphone = MicrophoneCapture { [weak self] buffer in
                self?.emit(channel: .me, buffer: buffer)
            }
            try microphone.start()
            self.microphone = microphone
        } else {
            microphone?.stop()
            microphone = nil
        }
    }

    public func stop() {
        systemTap?.stop()
        systemTap = nil
        microphone?.stop()
        microphone = nil
        lock.lock()
        continuation?.finish()
        continuation = nil
        stream = nil
        lock.unlock()
        isRunning = false
    }

    private func emit(channel: AudioChannel, buffer: AVAudioPCMBuffer) {
        lock.lock()
        let continuation = self.continuation
        lock.unlock()
        continuation?.yield(TaggedAudioBuffer(channel: channel, buffer: buffer))
    }
}
