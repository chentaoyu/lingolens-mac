import AppKit
import Combine
import Sparkle

/// Sparkle 2 自动更新的薄封装：启动时按 Info.plist 配置自动检查，并提供手动"检查更新"。
@MainActor
final class AppUpdater: ObservableObject {
    static let shared = AppUpdater()

    @Published private(set) var canCheckForUpdates = false

    private let controller = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    private init() {
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        // 菜单栏应用默认不在前台，先激活，否则更新窗口会被别的应用挡住。
        NSApp.activate()
        controller.checkForUpdates(nil)
    }

    /// 形如 "v0.1.2 (2)"。
    static var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "v\(version) (\(build))"
    }
}
