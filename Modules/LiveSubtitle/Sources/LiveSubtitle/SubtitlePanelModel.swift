import Foundation
import Settings

@MainActor
public final class SubtitlePanelModel: ObservableObject {
    public let store: SubtitleStore
    @Published public var settings: SubtitleSettings
    @Published public var clickThrough = false

    public init(store: SubtitleStore, settings: SubtitleSettings) {
        self.store = store
        self.settings = settings
    }
}
