import AudioCapture
import Foundation
import Testing
@testable import Meetings

private func makeTempRoot() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("LingoMeetings-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Suite("会议存储")
struct MeetingStoreTests {
    @Test("创建、追加、读取与纪要保存")
    func roundTrip() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MeetingStore(root: root)

        let meta = try await store.create(
            title: "周会",
            languages: [.other: "en", .me: "zh-Hans"],
            startedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        #expect(meta.title == "周会")
        #expect(meta.languages["other"] == "en")

        let first = TranscriptEntry(speaker: .other, text: "Hello")
        let second = TranscriptEntry(speaker: .me, text: "你好", translation: "Hello")
        try await store.append(first, to: meta.id)
        try await store.append(second, to: meta.id)

        let loaded = try await store.load(id: meta.id)
        #expect(loaded.entries.count == 2)
        #expect(loaded.entries[0].text == "Hello")
        #expect(loaded.entries[1].translation == "Hello")

        try await store.saveMinutes("# 纪要", for: meta.id)
        let withMinutes = try await store.load(id: meta.id)
        #expect(withMinutes.minutes == "# 纪要")

        let list = try await store.list()
        #expect(list.count == 1)
        #expect(list[0].hasMinutes)
    }

    @Test("编辑单条转写")
    func editEntry() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MeetingStore(root: root)
        let meta = try await store.create(title: "T", languages: [.other: "en"])
        let entry = TranscriptEntry(speaker: .other, text: "original")
        try await store.append(entry, to: meta.id)
        try await store.updateEntry(meetingID: meta.id, entryID: entry.id, text: "edited")

        let loaded = try await store.load(id: meta.id)
        #expect(loaded.entries.first?.text == "edited")
    }

    @Test("结束会议记录结束时间与时长")
    func finishMeeting() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MeetingStore(root: root)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let meta = try await store.create(title: nil, languages: [:], startedAt: start)
        try await store.finish(id: meta.id, endedAt: start.addingTimeInterval(90))

        let loaded = try await store.load(id: meta.id)
        #expect(loaded.meta.endedAt != nil)
        #expect(abs(loaded.meta.duration - 90) < 0.01)
    }
}

@Suite("长会议切段")
struct MeetingSegmenterTests {
    private func entry(_ text: String) -> TranscriptEntry {
        TranscriptEntry(speaker: .other, text: text)
    }

    @Test("中文按字估算、英文按四字符估算")
    func tokenEstimate() {
        #expect(MeetingSegmenter.estimatedTokens("你好世界") == 4)
        #expect(MeetingSegmenter.estimatedTokens("hello world") >= 2)
    }

    @Test("超过上下文一半才切段")
    func needsSegmentation() {
        let entries = (0..<100).map { _ in entry(String(repeating: "字", count: 20)) }
        #expect(MeetingSegmenter.needsSegmentation(entries, contextLength: 4096))
        #expect(!MeetingSegmenter.needsSegmentation([entry("短句")], contextLength: 32768))
    }

    @Test("按预算切段且顺序保持")
    func segments() {
        let entries = (0..<10).map { entry("第\($0)句" + String(repeating: "内容", count: 20)) }
        let chunks = MeetingSegmenter.segments(entries, tokenBudget: 80)
        #expect(chunks.count > 1)
        #expect(chunks.flatMap { $0 }.map(\.id) == entries.map(\.id))
    }
}

@Suite("纪要模板")
struct MinutesTemplateTests {
    @Test("默认包含标准模板，且标准模板不可删除")
    func standardTemplate() async {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("templates-\(UUID().uuidString).json")
        let store = MinutesTemplateStore(fileURL: url)
        let templates = await store.all()
        #expect(templates.contains { $0.id == MinutesTemplate.standardID })

        await store.delete(id: MinutesTemplate.standardID)
        #expect(await store.all().contains { $0.id == MinutesTemplate.standardID })

        let custom = await store.add(name: "自定义", prompt: "总结")
        await store.delete(id: custom.id)
        #expect(!(await store.all().contains { $0.id == custom.id }))
        try? FileManager.default.removeItem(at: url)
    }

    @Test("纪要提示词包含模板、语言与转写")
    func prompt() {
        let messages = MinutesPrompt.messages(
            template: .standard,
            source: "[10:00:00] 对方：hello",
            targetLanguage: "简体中文"
        )
        #expect(messages.count == 2)
        #expect(messages[0].content.contains("摘要"))
        #expect(messages[0].content.contains("简体中文"))
        #expect(messages[1].content.contains("hello"))
    }
}
