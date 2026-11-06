import AudioCapture
import Foundation

public struct SubtitleLine: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let channel: AudioChannel
    public var text: String
    public var translation: String?
    public var isFinal: Bool
    public var failed: Bool
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        channel: AudioChannel,
        text: String,
        translation: String? = nil,
        isFinal: Bool,
        failed: Bool = false,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.channel = channel
        self.text = text
        self.translation = translation
        self.isFinal = isFinal
        self.failed = failed
        self.timestamp = timestamp
    }
}
