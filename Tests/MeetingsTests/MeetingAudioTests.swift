import AudioCapture
import Foundation
import Testing
@testable import Meetings

@Suite("会议录音登记")
struct MeetingAudioTests {
    private func makeStore() -> (MeetingStore, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LingoMeetingAudio-\(UUID().uuidString)", isDirectory: true)
        return (MeetingStore(root: root), root)
    }

    @Test("录音文件名登记进 meta")
    func recordsAudioFiles() async throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let meta = try await store.create(languages: [.other: "zh-Hans", .me: "zh-Hans"])
        let otherURL = await store.audioFileURL(id: meta.id, channel: .other)
        try FileManager.default.createDirectory(
            at: otherURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data([0x00]).write(to: otherURL)

        try await store.setAudioFiles(id: meta.id, files: [.other: otherURL])

        let reloaded = try await store.loadMeta(id: meta.id)
        #expect(reloaded.audioFiles?["other"] == "audio-other.m4a")
        #expect(reloaded.audioFiles?["me"] == nil)
    }

    @Test("旧会议数据没有 audioFiles 字段也能解码")
    func decodesLegacyMeta() throws {
        let json = """
        {"id":"2026-11-09-102930","endedAt":"2026-11-09T02:34:45Z","languages":{"me":"zh-Hans","other":"zh-Hans"},"startedAt":"2026-11-09T02:29:30Z","title":"会议 11月9日 10:29"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let meta = try decoder.decode(MeetingMeta.self, from: Data(json.utf8))
        #expect(meta.audioFiles == nil)
        #expect(meta.id == "2026-11-09-102930")
    }

    @Test("录音路径按通道区分")
    func audioFileURLPerChannel() async {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let other = await store.audioFileURL(id: "abc", channel: .other)
        let me = await store.audioFileURL(id: "abc", channel: .me)
        #expect(other.lastPathComponent == "audio-other.m4a")
        #expect(me.lastPathComponent == "audio-me.m4a")
        #expect(other != me)
    }
}
