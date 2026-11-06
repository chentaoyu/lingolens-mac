import AudioCapture
import Foundation

public struct MeetingMeta: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var startedAt: Date
    public var endedAt: Date?
    public var languages: [String: String]

    public init(id: String, title: String, startedAt: Date, endedAt: Date? = nil, languages: [String: String]) {
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.languages = languages
    }

    public var duration: TimeInterval {
        (endedAt ?? Date()).timeIntervalSince(startedAt)
    }
}

public struct TranscriptEntry: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var time: Date
    public var speaker: AudioChannel
    public var text: String
    public var translation: String?

    public init(
        id: UUID = UUID(),
        time: Date = Date(),
        speaker: AudioChannel,
        text: String,
        translation: String? = nil
    ) {
        self.id = id
        self.time = time
        self.speaker = speaker
        self.text = text
        self.translation = translation
    }
}

public struct MeetingSummary: Sendable, Equatable, Identifiable {
    public var meta: MeetingMeta
    public var hasMinutes: Bool

    public var id: String { meta.id }

    public init(meta: MeetingMeta, hasMinutes: Bool) {
        self.meta = meta
        self.hasMinutes = hasMinutes
    }
}

public struct MeetingDetail: Sendable, Equatable {
    public var meta: MeetingMeta
    public var entries: [TranscriptEntry]
    public var minutes: String?

    public init(meta: MeetingMeta, entries: [TranscriptEntry], minutes: String?) {
        self.meta = meta
        self.entries = entries
        self.minutes = minutes
    }
}

public enum MeetingError: Error, LocalizedError, Equatable, Sendable {
    case meetingNotFound(String)
    case readFailed(String)
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .meetingNotFound(id): return "找不到会议：\(id)"
        case let .readFailed(message): return "读取会议数据失败：\(message)"
        case let .writeFailed(message): return "写入会议数据失败：\(message)"
        }
    }
}
