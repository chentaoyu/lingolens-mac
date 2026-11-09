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

    /// 一次判定的全部原始信息，便于在日志里定位「明明授权了却提示未授权」。
    public struct Diagnosis: Sendable, Equatable {
        public let inProcess: Bool
        public let childProcess: Bool?
        public let state: AccessibilityTrustState

        public init(inProcess: Bool, childProcess: Bool?, state: AccessibilityTrustState) {
            self.inProcess = inProcess
            self.childProcess = childProcess
            self.state = state
        }
    }

    /// 综合判断。
    ///
    /// 只用本进程的判定。曾经想靠「起子进程读同一个二进制」区分「真没授权」和
    /// 「授权了但本进程没生效」，实测行不通：子进程的 TCC 身份跟随**责任进程**
    /// （也就是本应用），拿到的仍是同样结果，永远判不出 needsRestart。
    public static func resolvedState() -> AccessibilityTrustState {
        diagnose().state
    }

    public static func diagnose() -> Diagnosis {
        let trusted = isTrusted
        return Diagnosis(
            inProcess: trusted,
            childProcess: nil,
            state: trusted ? .granted : .denied
        )
    }

    /// 让系统把**当前正在运行的这份二进制**登记到辅助功能列表里，并弹出授权提示。
    ///
    /// 关键点：TCC 条目是按代码签名绑定的，ad-hoc 签名每次构建 cdhash 都变，
    /// 所以老条目看着是「开着的」，却对不上现在跑的这份。让当前进程自己申请，
    /// 系统登记的才是这一份。
    @discardableResult
    public static func requestRegistration() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
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
