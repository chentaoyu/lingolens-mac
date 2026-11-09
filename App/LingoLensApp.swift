import ApplicationServices
import Foundation
import SwiftUI

/// 入口包装：在 SwiftUI 起来之前处理一次性命令行开关。
///
/// 授权复查必须用「同一个二进制、全新进程」跑，才能绕开当前进程里缓存的 TCC 判定；
/// 这个判断要早于 SwiftUI 初始化，否则拿不到准确结果也退出不干净。
@main
enum LingoLensMain {
    static func main() {
        if ProcessInfo.processInfo.arguments.contains("--accessibility-trust-check") {
            let trusted = AXIsProcessTrusted() ? "1" : "0"
            FileHandle.standardOutput.write(Data((trusted + "\n").utf8))
            exit(0)
        }
        LingoLensApp.main()
    }
}

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
            // 品牌标志的单色 template 版本，系统自动适配浅色 / 深色菜单栏。
            Label { Text("LingoLens") } icon: { Image("MenuBarIcon") }
        }
        .menuBarExtraStyle(.window)
    }
}
