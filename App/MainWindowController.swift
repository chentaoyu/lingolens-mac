import AppKit
import SwiftUI

/// 用 AppKit 管理主窗口，便于在启动/菜单栏点击时可靠地显示。
@MainActor
final class MainWindowController {
    static let shared = MainWindowController()

    private var window: NSWindow?

    private init() {}

    func show() {
        if window == nil {
            let hosting = NSHostingController(
                rootView: MainWindowView().environmentObject(AppEnvironment.shared)
            )
            let window = NSWindow(contentViewController: hosting)
            window.title = "LingoLens"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 940, height: 660))
            window.contentMinSize = NSSize(width: 880, height: 580)
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }

        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
