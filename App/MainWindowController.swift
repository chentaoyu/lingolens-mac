import AppKit
import SwiftUI

/// 用 AppKit 管理主窗口，便于在启动/菜单栏点击时可靠地显示。
@MainActor
final class MainWindowController {
    static let shared = MainWindowController()

    private var window: NSWindow?
    private var keyMonitor: Any?

    private init() {}

    func show() {
        if window == nil {
            let hosting = NSHostingController(
                rootView: MainWindowView().environmentObject(AppEnvironment.shared)
            )
            let window = LingoLensWindow(contentViewController: hosting)
            window.title = "LingoLens"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            // 会议页是转写 / 纪要左右分栏，默认给到原型同量级的宽度。
            window.setContentSize(NSSize(width: 1120, height: 700))
            window.contentMinSize = NSSize(width: 940, height: 600)
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
            installShortcuts()
        }

        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - 快捷键

    /// 菜单栏常驻应用没有可见菜单栏，这里用本地事件监听实现 ⌘1–⌘4 切页、⌘, 打开设置。
    private func installShortcuts() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Esc 关闭主窗口；正在编辑文本时交给输入控件处理。
            if event.keyCode == 53,
               let window = self?.window,
               window.isKeyWindow {
                let responder = window.firstResponder
                if !(responder is NSText), !(responder is NSTextView) {
                    window.performClose(nil)
                    return nil
                }
                return event
            }

            guard event.modifierFlags.contains(.command),
                  let characters = event.charactersIgnoringModifiers
            else { return event }

            if let index = Int(characters),
               index >= 1, index <= MainTab.allCases.count {
                AppEnvironment.shared.mainTab = MainTab.allCases[index - 1]
                return nil
            }
            // 中文输入法下 charactersIgnoringModifiers 会给出全角逗号，按物理键兜底。
            if characters == "," || characters == "，" || event.keyCode == 43 {
                AppEnvironment.shared.mainTab = .settings
                return nil
            }
            if characters.lowercased() == "w" {
                self?.window?.performClose(nil)
                return nil
            }
            return event
        }
    }
}

/// Esc 关闭主窗口；文本编辑等场景会先被输入控件消费。
private final class LingoLensWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        performClose(nil)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            performClose(nil)
            return
        }
        super.keyDown(with: event)
    }
}
