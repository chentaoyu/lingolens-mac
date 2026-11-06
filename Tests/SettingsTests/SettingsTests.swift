import Foundation
import Testing
@testable import Settings
@testable import LLMClient

@Suite("设置")
struct AppSettingsTests {
    @Test("场景默认值与文档一致")
    func sceneDefaults() {
        let settings = AppSettings()
        #expect(settings.scene(.selectionTranslation).parameters == .selectionTranslation)
        #expect(settings.scene(.liveSubtitle).parameters == .liveSubtitle)
        #expect(settings.scene(.meetingMinutes).parameters == .meetingMinutes)
        #expect(settings.scene(.liveSubtitle).useResidentModel == true)
    }

    @Test("缺少字段的 JSON 使用默认值")
    func resilientDecoding() throws {
        let json = #"{"residentModelID":"/models/qwen"}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(settings.residentModelID == "/models/qwen")
        #expect(settings.scanRoots.count == 3)
        #expect(settings.general.targetLanguage == "zh-Hans")
        #expect(settings.general.hotkey == .defaultSelection)
        #expect(settings.service(for: "x").idleUnloadMinutes == 10)
        #expect(settings.scene(.meetingMinutes).parameters.maxTokens == 4096)
    }

    @Test("缺省字段的场景参数在解码时保留")
    func partialSceneDecoding() throws {
        let json = #"""
        {"scenes":{"selectionTranslation":{"useResidentModel":false,"modelID":"m1","parameters":{"temperature":0.9}}}}
        """#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        let scene = settings.scene(.selectionTranslation)
        #expect(scene.useResidentModel == false)
        #expect(scene.modelID == "m1")
        #expect(scene.parameters.temperature == 0.9)
        #expect(scene.parameters.maxTokens == 1024)
    }

    @Test("编码与解码往返一致")
    func roundTrip() throws {
        var settings = AppSettings(residentModelID: "abc")
        settings.setScene(SceneSettings(useResidentModel: false, modelID: "def", parameters: .meetingMinutes), for: .liveSubtitle)
        settings.setService(ServiceSettings(kvCacheBits: 8, maxKVCacheLength: 4096, idleUnloadMinutes: 3), for: "abc")

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        #expect(decoded == settings)
    }

    @Test("指定模型与常驻模型解析")
    func modelResolution() {
        var settings = AppSettings(residentModelID: "resident")
        #expect(settings.specificModelID(for: .selectionTranslation) == nil)

        settings.setScene(SceneSettings(useResidentModel: false, modelID: "specific", parameters: .selectionTranslation), for: .selectionTranslation)
        #expect(settings.specificModelID(for: .selectionTranslation) == "specific")
    }

    @Test("磁盘读写")
    func persistence() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("settings.json")

        let settings = AppSettings(residentModelID: "qwen")
        try SettingsPersistence.save(settings, to: fileURL)
        #expect(SettingsPersistence.load(from: fileURL) == settings)
        #expect(SettingsPersistence.load(from: directory.appendingPathComponent("missing.json")) == AppSettings())
    }

    @Test("SettingsStore 修改后落盘")
    @MainActor
    func storePersists() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("settings.json")

        let store = SettingsStore(fileURL: fileURL, settings: AppSettings())
        store.update { $0.residentModelID = "qwen" }
        #expect(store.settings.residentModelID == "qwen")
        store.saveNow()
        #expect(SettingsPersistence.load(from: fileURL).residentModelID == "qwen")
    }
}

@Suite("快捷键")
struct HotkeyTests {
    @Test("默认 ⌥D")
    func defaultHotkey() {
        let spec = HotkeySpec.defaultSelection
        #expect(spec.displayString == "⌥D")
        #expect(spec.matches(keyCode: 2, modifiers: HotkeySpec.optionModifier))
        #expect(!spec.matches(keyCode: 2, modifiers: HotkeySpec.commandModifier))
    }

    @Test("组合修饰符显示顺序")
    func modifierDisplay() {
        let spec = HotkeySpec(keyCode: 1, modifiers: HotkeySpec.commandModifier | HotkeySpec.shiftModifier)
        #expect(spec.displayString == "⇧⌘S")
    }

    @Test("修饰符归一化")
    func normalize() {
        #expect(HotkeySpec.normalizedModifiers(0xFFFF) == 256 | 512 | 2048 | 4096)
    }
}

@Suite("语言选择")
struct LanguageSettingsTests {
    @Test("音频会话默认自动识别对方语言")
    func audioLanguageDefaults() {
        let settings = AppSettings()
        #expect(settings.audioSession.otherLanguage == AudioLanguageSettings.automatic)
        #expect(settings.audioSession.meLanguage == "zh-Hans")
        #expect(AudioLanguageSettings.locales(for: AudioLanguageSettings.automatic) == ["zh-Hans", "en"])
        #expect(AudioLanguageSettings.locales(for: "ja") == ["ja"])
        #expect(AudioLanguageSettings.displayName(AudioLanguageSettings.automatic) == "自动识别")
    }

    @Test("字幕目标语言默认中文，旧版每路语言字段可以兼容解码")
    func subtitleTargetLanguage() throws {
        let json = #"""
        {"subtitle":{"other":{"translate":true,"targetLanguage":"en"},"me":{"translate":false,"targetLanguage":"en"}}}
        """#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(settings.subtitle.targetLanguage == "zh-Hans")
        #expect(settings.subtitle.other.translate == true)
        #expect(settings.subtitle.me.translate == false)

        var updated = settings
        updated.subtitle.targetLanguage = "en"
        let roundTrip = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(updated))
        #expect(roundTrip.subtitle.targetLanguage == "en")
    }

    @Test("语言标识归一：zh_CN 与 zh-Hans 视为同一门语言")
    func languageNormalization() {
        #expect(SubtitleLanguage.canonical("zh_CN") == "zh-Hans")
        #expect(SubtitleLanguage.canonical("zh-Hans") == "zh-Hans")
        #expect(SubtitleLanguage.canonical("zh_TW") == "zh-Hant")
        #expect(SubtitleLanguage.canonical("en_US") == "en")
        #expect(SubtitleLanguage.isSame("zh_CN", "zh-Hans"))
        #expect(!SubtitleLanguage.isSame("en", "zh-Hans"))
        #expect(!SubtitleLanguage.isSame("zh-Hant", "zh-Hans"))
        #expect(!SubtitleLanguage.isSame("", "zh-Hans"))
    }
}
