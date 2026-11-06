import AppKit
import ModelRuntime

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            NSApp.setActivationPolicy(.accessory)
            AppEnvironment.shared.start()

            // 菜单栏应用首次启动时给一个可见反馈；之后保持静默常驻。
            let key = "LingoLens.didOpenMainWindow"
            if !UserDefaults.standard.bool(forKey: key) {
                UserDefaults.standard.set(true, forKey: key)
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(400))
                    MainWindowController.shared.show()
                }
            }

        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task { @MainActor in
            await AppEnvironment.shared.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        // 兜底：若仍有残留的模型服务进程，同步发 SIGTERM。
        PIDRegistry(fileURL: RuntimePaths.standard().pidRegistryFile).terminateAll()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            MainActor.assumeIsolated {
                MainWindowController.shared.show()
            }
        }
        return true
    }
}
