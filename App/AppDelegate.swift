import AppKit
import ModelRuntime

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            // 是否显示 Dock 图标由设置决定，默认只在菜单栏常驻。
            NSApp.setActivationPolicy(
                UserDefaults.standard.bool(forKey: "showInDock") ? .regular : .accessory
            )
            AppEnvironment.shared.start()
            _ = AppUpdater.shared

            // 菜单栏应用首次启动时给一个可见反馈；之后保持静默常驻。
            let didOpenMainWindow = UserDefaults.standard.bool(forKey: "LingoLens.didOpenMainWindow")
            let didFinishOnboarding = UserDefaults.standard.bool(
                forKey: AppEnvironment.didFinishOnboardingKey
            )
            if !didOpenMainWindow {
                UserDefaults.standard.set(true, forKey: "LingoLens.didOpenMainWindow")
            }

            if !didOpenMainWindow || !didFinishOnboarding {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(400))
                    MainWindowController.shared.show()
                    guard !didFinishOnboarding else { return }
                    // 等窗口完成首帧再挂 sheet，否则会贴在空白窗口上。
                    try? await Task.sleep(for: .milliseconds(300))
                    AppEnvironment.shared.isOnboardingPresented = true
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
