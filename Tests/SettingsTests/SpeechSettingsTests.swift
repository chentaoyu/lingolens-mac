import Foundation
import Testing
@testable import ModelRuntime
@testable import Settings

@Suite("语音引擎设置")
struct SpeechSettingsTests {
    @Test("默认走系统识别")
    func defaults() {
        let settings = SpeechSettings()
        #expect(settings.engine == .apple)
        #expect(settings.hotwords.isEmpty)
    }

    @Test("词表拆分支持中英文逗号与换行")
    func splitsHotwords() {
        let settings = SpeechSettings(engine: .whisper, hotwords: "ES, API，PRD\ndeadline ,, ")
        #expect(settings.hotwordList == ["ES", "API", "PRD", "deadline"])
    }

    @Test("词表去重且忽略大小写")
    func dedupesHotwords() {
        let settings = SpeechSettings(engine: .whisper, hotwords: "ES, es, Es")
        #expect(settings.hotwordList == ["ES"])
    }

    @Test("词表上限 80 条")
    func capsHotwords() {
        let many = (0..<200).map { "term\($0)" }.joined(separator: ",")
        let settings = SpeechSettings(engine: .whisper, hotwords: many)
        #expect(settings.hotwordList.count == 80)
    }

    @Test("缺失字段时解码回落默认值")
    func decodesLegacy() throws {
        let settings = try JSONDecoder().decode(SpeechSettings.self, from: Data("{}".utf8))
        #expect(settings.engine == .apple)
    }
}
