import Foundation

/// Carbon 全局快捷键描述（RegisterEventHotKey 使用的键码与修饰符）。
public struct HotkeySpec: Codable, Sendable, Equatable {
    public var keyCode: UInt32
    public var modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    // Carbon 修饰符常量。
    public static let commandModifier: UInt32 = 256
    public static let shiftModifier: UInt32 = 512
    public static let optionModifier: UInt32 = 2048
    public static let controlModifier: UInt32 = 4096

    /// 默认 ⌥D（kVK_ANSI_D = 2）。
    public static let defaultSelection = HotkeySpec(keyCode: 2, modifiers: optionModifier)

    private enum CodingKeys: String, CodingKey {
        case keyCode, modifiers
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keyCode = try container.decodeIfPresent(UInt32.self, forKey: .keyCode) ?? Self.defaultSelection.keyCode
        modifiers = try container.decodeIfPresent(UInt32.self, forKey: .modifiers) ?? Self.defaultSelection.modifiers
    }

    public var displayString: String {
        var result = ""
        if modifiers & Self.controlModifier != 0 { result += "⌃" }
        if modifiers & Self.optionModifier != 0 { result += "⌥" }
        if modifiers & Self.shiftModifier != 0 { result += "⇧" }
        if modifiers & Self.commandModifier != 0 { result += "⌘" }
        result += Self.keyName(for: keyCode)
        return result
    }

    public func matches(keyCode: UInt32, modifiers: UInt32) -> Bool {
        self.keyCode == keyCode && self.modifiers == modifiers
    }

    /// 只保留快捷键常用的修饰符位。
    public static func normalizedModifiers(_ raw: UInt32) -> UInt32 {
        raw & (commandModifier | shiftModifier | optionModifier | controlModifier)
    }

    public static func keyName(for keyCode: UInt32) -> String {
        let names: [UInt32: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
            11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2",
            20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8",
            29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "↩", 37: "L",
            38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M",
            47: ".", 48: "⇥", 49: "Space", 50: "`", 51: "⌫", 53: "⎋"
        ]
        return names[keyCode] ?? "Key\(keyCode)"
    }
}
