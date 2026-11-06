import Foundation

/// 语言标识的归一与比较。
///
/// Speech 解析出来的 locale 可能是 `zh_CN`、`en_US`，设置里存的是 `zh-Hans`、`en`；
/// 比较「源语言是否等于目标语言」前先归一到「语言 + 文字」。
public enum SubtitleLanguage {
    public static func canonical(_ identifier: String) -> String {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let locale = Locale(identifier: trimmed)
        guard let code = locale.language.languageCode?.identifier.lowercased() else {
            return trimmed.lowercased()
        }

        if code == "zh" {
            switch locale.language.script?.identifier {
            case "Hant": return "zh-Hant"
            case "Hans": return "zh-Hans"
            default: break
            }
            if let region = locale.language.region?.identifier.uppercased(),
               ["TW", "HK", "MO"].contains(region) {
                return "zh-Hant"
            }
            return "zh-Hans"
        }
        return code
    }

    /// 同一门语言（简繁算不同）时返回 true，用来跳过「中文译中文」这类无意义翻译。
    public static func isSame(_ lhs: String, _ rhs: String) -> Bool {
        let left = canonical(lhs)
        let right = canonical(rhs)
        guard !left.isEmpty, !right.isEmpty else { return false }
        return left == right
    }
}
