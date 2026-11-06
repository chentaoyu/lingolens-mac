import Foundation
import Testing
@testable import SelectionTranslate
@testable import Settings

@Suite("翻译方向")
struct TranslationDirectionTests {
    @Test("英文原文配中文目标语言保持不变")
    func englishToChinese() {
        let target = TranslationDirection.resolvedTargetLanguage(
            preferred: "zh-Hans",
            sourceText: "The quick brown fox jumps over the lazy dog."
        )
        #expect(target == "zh-Hans")
    }

    @Test("中文原文配中文目标语言时改译英文")
    func chineseToEnglish() {
        let target = TranslationDirection.resolvedTargetLanguage(
            preferred: "zh-Hans",
            sourceText: "今天天气很好，我们一起去公园散步吧。"
        )
        #expect(target == "en")
    }

    @Test("目标语言为英文且原文也是英文时回退中文")
    func englishFallback() {
        let target = TranslationDirection.resolvedTargetLanguage(
            preferred: "en",
            sourceText: "This is an English sentence used for language detection."
        )
        #expect(target == "zh-Hans")
    }

    @Test("空文本使用偏好语言")
    func emptyText() {
        #expect(TranslationDirection.resolvedTargetLanguage(preferred: "ja", sourceText: "   ") == "ja")
    }

    @Test("语言代码忽略地区后缀")
    func baseCode() {
        #expect(TranslationDirection.baseCode("zh-Hans") == "zh")
        #expect(TranslationDirection.baseCode("EN") == "en")
    }
}

@Suite("翻译提示词")
struct TranslationPromptTests {
    @Test("提示词包含目标语言并约束只输出译文")
    func prompt() {
        let messages = TranslationPrompt.messages(text: "hello", targetLanguage: "zh-Hans")
        #expect(messages.count == 2)
        #expect(messages[0].role == .system)
        #expect(messages[0].content.contains("简体中文"))
        #expect(messages[0].content.contains("只输出译文"))
        #expect(messages[1].content == "hello")
    }

    @Test("支持的目标语言包含中英日韩")
    func supportedLanguages() {
        let ids = TranslationPrompt.supportedTargetLanguages.map(\.id)
        #expect(ids.contains("zh-Hans"))
        #expect(ids.contains("en"))
        #expect(ids.contains("ja"))
        #expect(ids.contains("ko"))
    }
}

@Suite("模型错误")
struct ModelResolutionErrorTests {
    @Test("错误描述可读")
    func descriptions() {
        #expect(ModelResolutionError.noResidentModel.errorDescription?.isEmpty == false)
        #expect(ModelResolutionError.modelUnavailable("Qwen").errorDescription?.contains("Qwen") == true)
    }
}
