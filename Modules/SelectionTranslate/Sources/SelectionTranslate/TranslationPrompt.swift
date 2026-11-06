import Foundation
import LLMClient
import NaturalLanguage

public enum TranslationDirection {
    /// 目标语言与原文相同时改译英文（见设计文档 7）。
    public static func resolvedTargetLanguage(preferred: String, sourceText: String) -> String {
        guard let detected = detectLanguage(of: sourceText) else { return preferred }
        if baseCode(detected) == baseCode(preferred) {
            return baseCode(preferred) == "en" ? "zh-Hans" : "en"
        }
        return preferred
    }

    public static func detectLanguage(of text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        return recognizer.dominantLanguage?.rawValue
    }

    static func baseCode(_ identifier: String) -> String {
        String(identifier.split(separator: "-").first ?? Substring(identifier)).lowercased()
    }
}

public enum TranslationPrompt {
    public static func messages(text: String, targetLanguage: String) -> [ChatMessage] {
        [
            .system(systemMessage(targetLanguage: targetLanguage)),
            .user(text)
        ]
    }

    public static func systemMessage(targetLanguage: String) -> String {
        """
        你是一名专业翻译引擎。把用户输入的文本翻译成\(languageName(targetLanguage))。
        只输出译文本身，不要解释、不要加引号、不要重复原文；保留原文的段落、列表与代码格式。
        """
    }

    public static func languageName(_ identifier: String) -> String {
        Locale(identifier: "zh-Hans").localizedString(forIdentifier: identifier) ?? identifier
    }

    public static let supportedTargetLanguages: [(id: String, name: String)] = [
        ("zh-Hans", "简体中文"),
        ("zh-Hant", "繁體中文"),
        ("en", "English"),
        ("ja", "日本語"),
        ("ko", "한국어"),
        ("fr", "Français"),
        ("de", "Deutsch"),
        ("es", "Español"),
        ("ru", "Русский")
    ]
}
