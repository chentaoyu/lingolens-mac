import SwiftUI

@main
struct LingoLensApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var environment = AppEnvironment.shared

    var body: some Scene {
        // 主窗口统一由 MainWindowController 创建，避免 SwiftUI Window 场景
        // 和 AppKit 窗口两套生命周期互相打架（标题、尺寸、关闭行为不一致）。
        MenuBarExtra {
            MenuBarView()
                .environmentObject(environment)
        } label: {
            Label("LingoLens", systemImage: "character.bubble")
        }
        .menuBarExtraStyle(.window)
    }
}
