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
    private var frameObservers: [NSObjectProtocol] = []
    private let frameDefaultsKey = "subtitlePanelFrame"

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
            restoreOrPosition(panel)
        }
        isVisible = true
    }

    public func hide() {
        saveFrame()
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
        observeFrame(panel)

        settingsStore.$settings
            .map(\.subtitle)
            .removeDuplicates()
            .sink { [weak model] subtitle in
                model?.settings = subtitle
            }
            .store(in: &cancellables)

        return panel
    }

    /// 恢复用户上次拖动后的位置；窗口可能已经不在任何屏幕上（外接屏拔掉），这时回到底部默认位置。
    private func restoreOrPosition(_ panel: NSPanel) {
        if let saved = UserDefaults.standard.string(forKey: frameDefaultsKey) {
            let frame = NSRectFromString(saved)
            if frame.width > 200, frame.height > 80,
               NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) {
                panel.setFrame(frame, display: true)
                return
            }
        }
        position(panel)
    }

    private func observeFrame(_ panel: NSPanel) {
        let center = NotificationCenter.default
        for name in [NSWindow.didMoveNotification, NSWindow.didEndLiveResizeNotification] {
            let token = center.addObserver(forName: name, object: panel, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.saveFrame()
                }
            }
            frameObservers.append(token)
        }
    }

    private func saveFrame() {
        guard let panel, panel.isVisible else { return }
        UserDefaults.standard.set(NSStringFromRect(panel.frame), forKey: frameDefaultsKey)
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
