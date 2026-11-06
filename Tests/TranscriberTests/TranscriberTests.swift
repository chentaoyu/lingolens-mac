import Foundation
import Speech
import Testing
@testable import Transcriber

@Suite("语音模型语言")
struct SpeechAssetManagerTests {
    @Test("支持语言列表非空")
    func supportedLocales() async {
        let locales = await SpeechAssetManager.supportedLocaleIdentifiers()
        #expect(!locales.isEmpty)
    }

    @Test("不支持的语言返回 nil")
    func unsupportedLocale() async {
        let resolved = await SpeechAssetManager.resolvedLocale(for: "zz-ZZ")
        #expect(resolved == nil)
    }
}
