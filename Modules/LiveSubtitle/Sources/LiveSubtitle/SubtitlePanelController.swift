import AppKit
import Combine
import Settings
import SwiftUI

final class SubtitlePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
public final class SubtitlePanelController: ObservableObject {
    @Published public private(set) var isVisible = false
    @Published public private(set) var isClickThrough = false

    private let store: SubtitleStore
    private let settingsStore: SettingsStore
    private var model: SubtitlePanelModel?
    private var panel: SubtitlePanel?
    private var cancellables = Set<AnyCancellable>()

    public init(store: SubtitleStore, settingsStore: SettingsStore) {
        self.store = store
        self.settingsStore = settingsStore
    }

    public func show() {
        let isFirstShow = panel == nil
        let panel = ensurePanel()
        panel.orderFrontRegardless()
        // 首次显示放到屏幕底部；之后保留用户拖动后的位置和大小。
        // 需在 orderFront 之后设置，否则首次布局会把窗口收缩成内容尺寸。
        if isFirstShow {
            position(panel)
        }
        isVisible = true
    }

    public func hide() {
        panel?.orderOut(nil)
        isVisible = false
    }

    public func toggleVisibility() {
        isVisible ? hide() : show()
    }

    public func toggleClickThrough() {
        guard let model else { return }
        model.clickThrough.toggle()
        panel?.ignoresMouseEvents = model.clickThrough
        isClickThrough = model.clickThrough
    }

    private func ensurePanel() -> SubtitlePanel {
        if let panel { return panel }

        let model = SubtitlePanelModel(store: store, settings: settingsStore.settings.subtitle)
        model.onUpdateSettings = { [weak settingsStore] subtitle in
            settingsStore?.update { $0.subtitle = subtitle }
        }
        let view = SubtitlePanelView(
            model: model,
            store: store,
            onClose: { [weak self] in self?.hide() },
            onToggleClickThrough: { [weak self] in self?.toggleClickThrough() }
        )
        let hosting = NSHostingView(rootView: view)
        // 不随内容理想尺寸自动缩放窗口，尺寸由面板自身决定。
        hosting.sizingOptions = []

        let panel = SubtitlePanel(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 240),
            styleMask: [.nonactivatingPanel, .titled, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hosting
        panel.title = "LingoLens 字幕"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true

        self.model = model
        self.panel = panel

        settingsStore.$settings
            .map(\.subtitle)
            .removeDuplicates()
            .sink { [weak model] subtitle in
                model?.settings = subtitle
            }
            .store(in: &cancellables)

        return panel
    }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let width = min(1000, visible.width * 0.72)
        let height = min(320, visible.height * 0.35)
        let frame = NSRect(
            x: visible.midX - width / 2,
            y: visible.minY + 60,
            width: width,
            height: height
        )
        panel.setFrame(frame, display: true)
    }
}
