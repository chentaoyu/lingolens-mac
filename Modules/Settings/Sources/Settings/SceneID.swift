import Foundation
import LLMClient

public enum SceneID: String, Codable, CaseIterable, Sendable {
    case selectionTranslation
    case liveSubtitle
    case meetingMinutes

    public var displayName: String {
        switch self {
        case .selectionTranslation: return "划词翻译"
        case .liveSubtitle: return "实时字幕"
        case .meetingMinutes: return "会议纪要"
        }
    }

    public var subtitle: String {
        switch self {
        case .selectionTranslation: return "偶发、短文本，首字延迟优先"
        case .liveSubtitle: return "持续、高频，1–3 句"
        case .meetingMinutes: return "会后一次性、长输入，质量优先"
        }
    }

    public var defaultParameters: GenerationParameters {
        switch self {
        case .selectionTranslation: return .selectionTranslation
        case .liveSubtitle: return .liveSubtitle
        case .meetingMinutes: return .meetingMinutes
        }
    }
}
