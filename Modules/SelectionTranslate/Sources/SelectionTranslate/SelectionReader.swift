import AppKit
import ApplicationServices
import Foundation

public enum SelectionSource: String, Sendable {
    case accessibility
    case clipboard
}

public struct SelectionResult: Sendable, Equatable {
    public let text: String
    public let source: SelectionSource

    public init(text: String, source: SelectionSource) {
        self.text = text
        self.source = source
    }
}

@MainActor
public protocol SelectedTextProviding {
    func readSelectedText() async -> SelectionResult?
}

public enum AccessibilityPermission {
    public static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// 弹出系统授权提示（只会出现一次，之后需到系统设置里手动开启）。
    public static func request() {
        // kAXTrustedCheckOptionPrompt 是全局 var，Swift 6 下不可直接读取；使用其字符串值。
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    public static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

/// 先读 Accessibility 的选中文本，失败时用剪贴板兜底。
public struct SystemSelectionReader: SelectedTextProviding {
    public init() {}

    public func readSelectedText() async -> SelectionResult? {
        if let text = Self.accessibilitySelectedText(), !text.isEmpty {
            return SelectionResult(text: text, source: .accessibility)
        }
        if let text = await Self.clipboardSelectedText(), !text.isEmpty {
            return SelectionResult(text: text, source: .clipboard)
        }
        return nil
    }

    public static func accessibilitySelectedText() -> String? {
        guard let application = NSWorkspace.shared.frontmostApplication else { return nil }
        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)

        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            applicationElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        ) == .success, let focusedValue else { return nil }

        let focusedElement = focusedValue as! AXUIElement
        var selectedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focusedElement,
            kAXSelectedTextAttribute as CFString,
            &selectedValue
        ) == .success, let text = selectedValue as? String, !text.isEmpty else { return nil }

        return text
    }

    /// 备份剪贴板 → 模拟 ⌘C → 读取 → 恢复。
    public static func clipboardSelectedText() async -> String? {
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard: pasteboard)
        let initialChangeCount = pasteboard.changeCount

        simulateCopy()

        var waited = 0
        var changed = false
        while waited < 400 {
            try? await Task.sleep(for: .milliseconds(20))
            waited += 20
            if pasteboard.changeCount != initialChangeCount {
                changed = true
                break
            }
        }

        // 没有变化说明当前没有可复制的选中内容，避免把旧剪贴板内容当成选中文本。
        guard changed else {
            snapshot.restore(to: pasteboard)
            return nil
        }

        let text = pasteboard.string(forType: .string)
        snapshot.restore(to: pasteboard)
        return text
    }

    public static func simulateCopy() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyCodeC: CGKeyCode = 0x08 // kVK_ANSI_C
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCodeC, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCodeC, keyDown: false)
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}

private struct PasteboardSnapshot {
    let items: [[NSPasteboard.PasteboardType: Data]]

    init(pasteboard: NSPasteboard) {
        var captured: [[NSPasteboard.PasteboardType: Data]] = []
        for item in pasteboard.pasteboardItems ?? [] {
            var contents: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    contents[type] = data
                }
            }
            captured.append(contents)
        }
        self.items = captured
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let restoredItems = items.map { contents -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in contents {
                item.setData(data, forType: type)
            }
            return item
        }
        if !restoredItems.isEmpty {
            pasteboard.writeObjects(restoredItems)
        }
    }
}
