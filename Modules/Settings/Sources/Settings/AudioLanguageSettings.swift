import Foundation

/// 音频会话里的语言选择：固定语言，或「自动识别」。
public enum AudioLanguageSettings {
    /// 自动识别的哨兵值，保存进设置文件。
    public static let automatic = "auto"

    /// 自动识别时同时挂的候选语言。
    /// 每多一种语言就要多跑一份 Speech 模型，中英两路已经覆盖主要会议场景。
    public static let automaticCandidates = ["zh-Hans", "en"]

    /// 把设置里的值展开成要交给 Speech 的语言列表。
    public static func locales(for identifier: String) -> [String] {
        identifier == automatic ? automaticCandidates : [identifier]
    }

    /// 界面上显示的名字：自动 / 语言名。
    public static func displayName(_ identifier: String) -> String {
        if identifier == automatic { return "自动识别" }
        return Locale(identifier: "zh-Hans").localizedString(forIdentifier: identifier) ?? identifier
    }
}
