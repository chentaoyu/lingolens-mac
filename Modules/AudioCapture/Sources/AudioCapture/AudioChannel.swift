import AVFoundation
import Foundation

/// 会议中的两路音频。
public enum AudioChannel: String, Codable, CaseIterable, Sendable {
    case me
    case other

    public var displayName: String {
        switch self {
        case .me: return "我"
        case .other: return "对方"
        }
    }
}

public struct TaggedAudioBuffer: @unchecked Sendable {
    public let channel: AudioChannel
    public let buffer: AVAudioPCMBuffer
    public let timestamp: Date

    public init(channel: AudioChannel, buffer: AVAudioPCMBuffer, timestamp: Date = Date()) {
        self.channel = channel
        self.buffer = buffer
        self.timestamp = timestamp
    }
}
