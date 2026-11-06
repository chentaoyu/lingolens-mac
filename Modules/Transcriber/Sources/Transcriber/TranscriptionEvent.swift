import AudioCapture
import Foundation

public struct TranscriptionEvent: Sendable, Equatable {
    public let channel: AudioChannel
    public let text: String
    public let isFinal: Bool
    public let timestamp: Date

    public init(channel: AudioChannel, text: String, isFinal: Bool, timestamp: Date = Date()) {
        self.channel = channel
        self.text = text
        self.isFinal = isFinal
        self.timestamp = timestamp
    }
}

public enum TranscriptionError: Error, LocalizedError, Sendable {
    case localeUnsupported(String)
    case assetInstallationFailed(String)
    case audioFormatUnavailable

    public var errorDescription: String? {
        switch self {
        case let .localeUnsupported(locale):
            return "系统语音识别不支持语言：\(locale)"
        case let .assetInstallationFailed(message):
            return "语音模型下载失败：\(message)"
        case .audioFormatUnavailable:
            return "无法准备语音识别所需的音频格式。"
        }
    }
}
