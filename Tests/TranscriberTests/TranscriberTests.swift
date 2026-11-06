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

@Suite("多语言结果取舍")
struct TranscriptionLanguageTrackerTests {
    private func finalCandidate(
        _ language: String,
        _ confidence: Double,
        start: Double
    ) -> TranscriptionCandidate {
        TranscriptionCandidate(
            language: language,
            text: "text-\(language)",
            isFinal: true,
            confidence: confidence,
            rangeStart: start,
            rangeEnd: start + 4
        )
    }

    @Test("第一条 final 决定语言并上屏")
    func firstFinalDecidesLanguage() {
        var tracker = TranscriptionLanguageTracker()
        #expect(!tracker.acceptsPartial("zh-Hans"))
        var accepted = tracker.acceptFinal(finalCandidate("zh-Hans", 0.97, start: 0))
        #expect(accepted)
        #expect(tracker.activeLanguage == "zh-Hans")
        #expect(tracker.acceptsPartial("zh-Hans"))
        #expect(!tracker.acceptsPartial("en"))
    }

    @Test("当前语言置信度低时切到明显更好的语言")
    func switchesWhenOtherLanguageIsClearlyBetter() {
        var tracker = TranscriptionLanguageTracker(initialLanguage: "zh-Hans")
        let first = tracker.acceptFinal(finalCandidate("zh-Hans", 0.65, start: 10))
        #expect(first)
        let switched = tracker.acceptFinal(finalCandidate("en", 0.98, start: 20))
        #expect(switched)
        #expect(tracker.activeLanguage == "en")
    }

    @Test("另一种语言只是噪声时不切换")
    func ignoresLowConfidenceNoise() {
        var tracker = TranscriptionLanguageTracker(initialLanguage: "zh-Hans")
        let first = tracker.acceptFinal(finalCandidate("zh-Hans", 0.97, start: 0))
        #expect(first)
        let noise = tracker.acceptFinal(finalCandidate("en", 0.21, start: 10))
        #expect(!noise)
        #expect(tracker.activeLanguage == "zh-Hans")
    }

    @Test("同一句已上屏时只切语言，不重复一行")
    func doesNotDuplicateSameUtterance() {
        var tracker = TranscriptionLanguageTracker(initialLanguage: "en")
        let first = tracker.acceptFinal(finalCandidate("en", 0.6, start: 5))
        #expect(first)
        let duplicate = tracker.acceptFinal(finalCandidate("zh-Hans", 0.97, start: 5.2))
        #expect(!duplicate)
        #expect(tracker.activeLanguage == "zh-Hans")
    }
}

@Suite("中英混说时等待另一种语言定稿")
struct OpenUtteranceTrackerTests {
    private func candidate(_ language: String, final: Bool, start: Double, end: Double) -> TranscriptionCandidate {
        TranscriptionCandidate(language: language, text: "t", isFinal: final, confidence: final ? 0.55 : 0, rangeStart: start, rangeEnd: end)
    }

    @Test("另一种语言这句还没定稿时继续等")
    func keepsHoldingWhileOtherLanguageIsOpen() {
        var tracker = OpenUtteranceTracker()
        tracker.note(candidate("zh-Hans", final: false, start: 0, end: 2))
        let held = candidate("en", final: true, start: 0, end: 4)
        #expect(tracker.shouldKeepHolding(held, heldFor: 3))
        #expect(!tracker.shouldKeepHolding(held, heldFor: OpenUtteranceTracker.maxHold))
    }

    @Test("另一种语言已定稿或只在说下一句时不再等")
    func releasesWhenOtherLanguageFinished() {
        var tracker = OpenUtteranceTracker()
        tracker.note(candidate("zh-Hans", final: false, start: 0, end: 2))
        tracker.note(candidate("zh-Hans", final: true, start: 0, end: 4))
        let held = candidate("en", final: true, start: 0, end: 4)
        #expect(!tracker.shouldKeepHolding(held, heldFor: 3))
        tracker.note(candidate("zh-Hans", final: false, start: 5, end: 6))
        #expect(!tracker.shouldKeepHolding(held, heldFor: 3))
    }
}
