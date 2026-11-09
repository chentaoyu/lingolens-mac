import AppKit
import ApplicationServices
import Foundation

/// 辅助功能授权状态。
///
/// 关键点：macOS 把 TCC 判定结果缓存在**进程**里。用户在系统设置里勾选之后，
/// 已经在运行的进程常常仍然读到 false，必须重启一次才生效。
/// 为了区分「真的没授权」和「授权了但本进程还没生效」，这里用一个**子进程**
/// 跑同一个二进制来读判定——同一个 app 身份、但进程是新的，不会被缓存影响。
public enum AccessibilityTrustState: Sendable, Equatable {
    /// 本进程可用。
    case granted
    /// 系统里也没授权。
    case denied
    /// 系统里已授权，但当前进程还没生效，需要重启应用。
    case needsRestart

    public var isUsable: Bool { self == .granted }
}

public enum AccessibilityPermission {
    /// 本进程的判定（会受进程级缓存影响）。
    public static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// 弹出系统授权提示（只会出现一次，之后需到系统设置里手动开启）。
    public static func request() {
        // kAXTrustedCheckOptionPrompt 是全局 var，Swift 6 下不可直接读取；使用其字符串值。
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// 综合判断：本进程可用就直接算已授权；否则起一个子进程复查。
    public static func resolvedState() -> AccessibilityTrustState {
        if isTrusted { return .granted }
        switch childProcessTrust() {
        case .some(true): return .needsRestart
        // 子进程也读不到就按「未授权」处理；子进程本身跑不起来时同样退回未授权，
        // 宁可多提示一次，也不要假装已授权让划词翻译失效。
        case .some(false), .none: return .denied
        }
    }

    /// 用同一个二进制起一个子进程读判定。返回 nil 表示没跑起来。
    public static func childProcessTrust() -> Bool? {
        guard let executable = Bundle.main.executableURL else { return nil }
        let process = Process()
        process.executableURL = executable
        process.arguments = ["--accessibility-trust-check"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        // 子进程只打印一行就退出；卡住时不要拖住 UI。
        let deadline = Date().addingTimeInterval(3)
        while process.isRunning, Date() < deadline {
            usleep(20_000)
        }
        if process.isRunning {
            process.terminate()
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        switch text {
        case "1": return true
        case "0": return false
        default: return nil
        }
    }

    public static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// 重启应用，让新的 TCC 判定生效。
    @MainActor
    public static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }
}

/// 先读 Accessibility 的选中文本，失败时用剪贴板兜底。
public struct SystemSelectionReader: SelectedTextProviding {
    public init() {}

    public func readSelectedText() async -> SelectionResult? {
        if let text = AccessibilitySelection.selectedText(), !text.isEmpty {
            return SelectionResult(text: text, source: .accessibility)
        }
        if let text = await AccessibilitySelection.clipboardSelectedText(), !text.isEmpty {
            return SelectionResult(text: text, source: .clipboard)
        }
        return nil
    }
}
