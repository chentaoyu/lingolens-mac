import AppKit

/// 回车键的交互规则：单独按回车立即翻译，带修饰键则保持原义（换行 / 重译）。
enum ReturnKeyRule {
    /// 主键盘回车（36）与小键盘 Enter（76）。
    static let keyCodes: Set<UInt16> = [36, 76]

    /// 是否应当立即提交：主键盘/小键盘回车，且不带 ⌘⌃⌥⇧。
    /// 大小写锁定、功能键标记不属于用户主动组合，忽略。
    static func submits(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        guard keyCodes.contains(keyCode) else { return false }
        let flags = modifiers.intersection(.deviceIndependentFlagsMask)
        return flags.subtracting([.function, .numericPad, .capsLock]).isEmpty
    }

    /// ⇧↩ / ⌥↩：在输入框里插入换行。
    static func insertsNewline(modifiers: NSEvent.ModifierFlags) -> Bool {
        let flags = modifiers.intersection(.deviceIndependentFlagsMask)
        return flags.contains(.shift) || flags.contains(.option)
    }
}
