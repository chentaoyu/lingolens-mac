import AudioCapture
import Foundation
import Settings
import Testing
import Transcriber
@testable import LiveSubtitle

@Suite("字幕规划")
struct SubtitlePlannerTests {
    private func id() -> UUID { UUID() }

    @Test("少量积压逐句翻译并携带前两句上下文")
    func individualBatches() {
        let first = PendingSubtitle(id: id(), text: "Hello")
        let second = PendingSubtitle(id: id(), text: "How are you")
        let batches = SubtitleTranslationPlanner.plan(
            pending: [first, second],
            context: ["Earlier one", "Earlier two", "Earlier three"]
        )
        #expect(batches.count == 2)
        #expect(batches[0].ids == [first.id])
        #expect(batches[0].context == ["Earlier two", "Earlier three"])
        #expect(batches[1].context == ["Earlier three", "Hello"])
    }

    @Test("积压超过阈值时合并为一次请求")
    func mergedBatch() {
        let pending = (0..<5).map { PendingSubtitle(id: id(), text: "line \($0)") }
        let batches = SubtitleTranslationPlanner.plan(pending: pending, context: ["ctx"])
        #expect(batches.count == 1)
        #expect(batches[0].ids == pending.map(\.id))
        #expect(batches[0].text == pending.map(\.text).joined(separator: "\n"))
        #expect(batches[0].context == ["ctx"])
    }

    @Test("按行分配译文")
    func distributeLines() {
        let ids = [id(), id()]
        let result = SubtitleTranslationParser.distribute("第一行\n第二行", ids: ids)
        #expect(result[ids[0]] == "第一行")
        #expect(result[ids[1]] == "第二行")
    }

    @Test("行数不匹配时整段给最后一句")
    func distributeMismatch() {
        let ids = [id(), id(), id()]
        let result = SubtitleTranslationParser.distribute("一整段译文", ids: ids)
        #expect(result.count == 1)
        #expect(result[ids[2]] == "一整段译文")
    }

    @Test("单句直接返回")
    func distributeSingle() {
        let id = id()
        #expect(SubtitleTranslationParser.distribute("你好", ids: [id]) == [id: "你好"])
    }
}

@Suite("字幕列表")
struct SubtitleStoreTests {
    @Test("partial 原地更新，final 复用同一行")
    @MainActor
    func partialThenFinal() {
        let store = SubtitleStore()
        #expect(store.apply(TranscriptionEvent(channel: .other, text: "Hel", isFinal: false)) == nil)
        store.apply(TranscriptionEvent(channel: .other, text: "Hello", isFinal: false))
        #expect(store.lines.count == 1)
        #expect(store.lines[0].text == "Hello")

        let id = store.apply(TranscriptionEvent(channel: .other, text: "Hello world", isFinal: true))
        #expect(id == store.lines[0].id)
        #expect(store.lines[0].isFinal)
        #expect(store.lines[0].text == "Hello world")
    }

    @Test("两路各自维护 partial")
    @MainActor
    func channelsAreIndependent() {
        let store = SubtitleStore()
        store.apply(TranscriptionEvent(channel: .me, text: "我", isFinal: false))
        store.apply(TranscriptionEvent(channel: .other, text: "对方", isFinal: false))
        #expect(store.lines.map(\.channel) == [.me, .other])
    }

    @Test("超出上限时裁掉旧行")
    @MainActor
    func trimsOldLines() {
        let store = SubtitleStore(maxLines: 2)
        for index in 0..<4 {
            store.apply(TranscriptionEvent(channel: .other, text: "line \(index)", isFinal: true))
        }
        #expect(store.lines.count == 2)
        #expect(store.lines.map(\.text) == ["line 2", "line 3"])
    }

    @Test("翻译与失败标记")
    @MainActor
    func translationState() {
        let store = SubtitleStore()
        let id = store.apply(TranscriptionEvent(channel: .other, text: "Hi", isFinal: true))
        store.setTranslation(lineID: id!, text: "你好")
        #expect(store.lines[0].translation == "你好")
        store.markFailed(lineID: id!)
        #expect(store.lines[0].failed)
    }
}

@Suite("翻译跳过规则")
struct SubtitleTranslationPolicyTests {
    @Test("源语言等于目标语言时不翻译")
    func skipsSameLanguage() {
        let enabled = SubtitleChannelSettings(translate: true)
        #expect(!SubtitleTranslationPolicy.shouldTranslate(
            channel: enabled, targetLanguage: "zh-Hans", sourceLanguage: "zh-Hans"
        ))
        #expect(!SubtitleTranslationPolicy.shouldTranslate(
            channel: enabled, targetLanguage: "zh-Hans", sourceLanguage: "zh_CN"
        ))
        #expect(SubtitleTranslationPolicy.shouldTranslate(
            channel: enabled, targetLanguage: "en", sourceLanguage: "zh-Hans"
        ))
        #expect(SubtitleTranslationPolicy.shouldTranslate(
            channel: enabled, targetLanguage: "zh-Hans", sourceLanguage: "en"
        ))
        #expect(SubtitleTranslationPolicy.shouldTranslate(
            channel: enabled, targetLanguage: "zh-Hans", sourceLanguage: nil
        ))
        #expect(!SubtitleTranslationPolicy.shouldTranslate(
            channel: SubtitleChannelSettings(translate: false), targetLanguage: "en", sourceLanguage: "zh-Hans"
        ))
    }
}
