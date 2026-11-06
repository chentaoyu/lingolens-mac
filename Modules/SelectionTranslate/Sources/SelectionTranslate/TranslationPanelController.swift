import AppKit
import SwiftUI

final class TranslationPanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

@MainActor
private final class TranslationPanelDelegate: NSObject, NSWindowDelegate {
    weak var model: TranslationPanelModel?
    var onHide: (() -> Void)?

    func windowDidResignKey(_ notification: Notification) {
        guard let model, !model.isPinned else { return }
        onHide?()
    }
}

@MainActor
public final class TranslationPanelController {
    private let service: TranslationService
    private var panel: TranslationPanel?
    private var model: TranslationPanelModel?
    private var delegate: TranslationPanelDelegate?

    public init(service: TranslationService) {
        self.service = service
    }

    public func show(text: String?, near point: NSPoint? = nil) {
        let panel = ensurePanel()
        guard let model else { return }

        let wasVisible = panel.isVisible
        model.targetOverride = nil
        if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            model.originalText = text
            model.retranslate()
        } else {
            model.prepareForManualInput()
        }

        position(panel, near: point ?? NSEvent.mouseLocation)
        if !wasVisible {
            panel.alphaValue = 0
        }
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        if !wasVisible {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        }
    }

    public func hide() {
        model?.cancel()
        panel?.orderOut(nil)
    }

    public func toggle(text: String?, near point: NSPoint? = nil) {
        if let panel, panel.isVisible {
            hide()
        } else {
            show(text: text, near: point)
        }
    }

    private func ensurePanel() -> TranslationPanel {
        if let panel {
            return panel
        }

        let model = TranslationPanelModel(service: service)
        let view = TranslationPanelView(model: model) { [weak self] in
            self?.hide()
        }
        let hostingView = NSHostingView(rootView: view)
        // 不随内容理想尺寸自动缩放窗口，尺寸由面板自身决定。
        hostingView.sizingOptions = []

        let panel = TranslationPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 280),
            styleMask: [.nonactivatingPanel, .titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.title = "LingoLens"
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
        panel.becomesKeyOnlyIfNeeded = false

        model.onClose = { [weak self] in
            self?.hide()
        }

        let delegate = TranslationPanelDelegate()
        delegate.model = model
        delegate.onHide = { [weak self] in
            self?.hide()
        }
        panel.delegate = delegate
        panel.onCancel = { [weak self] in
            self?.hide()
        }

        self.model = model
        self.panel = panel
        self.delegate = delegate
        return panel
    }

    private func position(_ panel: NSPanel, near point: NSPoint) {
        let size = panel.frame.size
        var origin = NSPoint(x: point.x + 12, y: point.y - size.height - 12)

        let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            origin.x = min(max(visible.minX + 8, origin.x), visible.maxX - size.width - 8)
            origin.y = min(max(visible.minY + 8, origin.y), visible.maxY - size.height - 8)
        }
        panel.setFrameOrigin(origin)
    }
}
