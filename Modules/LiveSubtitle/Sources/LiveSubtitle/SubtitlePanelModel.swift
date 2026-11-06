import Foundation
import Settings

@MainActor
public final class SubtitlePanelModel: ObservableObject {
    public let store: SubtitleStore
    @Published public var settings: SubtitleSettings
    @Published public var clickThrough = false
    /// 暂停时冻结当前显示的字幕，转写与翻译照常进行。
    @Published public private(set) var pausedLines: [SubtitleLine]?

    /// 浮窗内调整字号/透明度时写回设置。
    var onUpdateSettings: ((SubtitleSettings) -> Void)?

    public init(store: SubtitleStore, settings: SubtitleSettings) {
        self.store = store
        self.settings = settings
    }

    public var isPaused: Bool { pausedLines != nil }

    public func togglePause() {
        pausedLines = isPaused ? nil : store.lines
    }

    public func update(_ mutate: (inout SubtitleSettings) -> Void) {
        mutate(&settings)
        onUpdateSettings?(settings)
    }
}

/// 字号档位：紧凑 / 标准 / 大字。
public enum SubtitleSizePreset: Double, CaseIterable, Sendable {
    case compact = 16
    case standard = 20
    case large = 26

    public var title: String {
        switch self {
        case .compact: return "紧凑"
        case .standard: return "标准"
        case .large: return "大字"
        }
    }
}
