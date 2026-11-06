import Foundation
import LLMClient

public struct SceneSettings: Codable, Sendable, Equatable {
    public var useResidentModel: Bool
    public var modelID: String?
    public var parameters: GenerationParameters

    public init(useResidentModel: Bool = true, modelID: String? = nil, parameters: GenerationParameters) {
        self.useResidentModel = useResidentModel
        self.modelID = modelID
        self.parameters = parameters
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        useResidentModel = try container.decodeIfPresent(Bool.self, forKey: .useResidentModel) ?? true
        modelID = try container.decodeIfPresent(String.self, forKey: .modelID)
        parameters = try container.decodeIfPresent(GenerationParameters.self, forKey: .parameters)
            ?? .selectionTranslation
    }
}

/// 按模型保存的服务参数。
public struct ServiceSettings: Codable, Sendable, Equatable {
    public var kvCacheBits: Int?
    public var maxKVCacheLength: Int?
    public var idleUnloadMinutes: Int

    public init(kvCacheBits: Int? = nil, maxKVCacheLength: Int? = nil, idleUnloadMinutes: Int = 10) {
        self.kvCacheBits = kvCacheBits
        self.maxKVCacheLength = maxKVCacheLength
        self.idleUnloadMinutes = idleUnloadMinutes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kvCacheBits = try container.decodeIfPresent(Int.self, forKey: .kvCacheBits)
        maxKVCacheLength = try container.decodeIfPresent(Int.self, forKey: .maxKVCacheLength)
        idleUnloadMinutes = try container.decodeIfPresent(Int.self, forKey: .idleUnloadMinutes) ?? 10
    }
}

public struct GeneralSettings: Codable, Sendable, Equatable {
    public var targetLanguage: String
    public var hotkey: HotkeySpec
    public var launchAtLogin: Bool

    public init(targetLanguage: String = "zh-Hans", hotkey: HotkeySpec = .defaultSelection, launchAtLogin: Bool = false) {
        self.targetLanguage = targetLanguage
        self.hotkey = hotkey
        self.launchAtLogin = launchAtLogin
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        targetLanguage = try container.decodeIfPresent(String.self, forKey: .targetLanguage) ?? "zh-Hans"
        hotkey = try container.decodeIfPresent(HotkeySpec.self, forKey: .hotkey) ?? .defaultSelection
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
    }
}

public struct SubtitleChannelSettings: Codable, Sendable, Equatable {
    public var translate: Bool
    public var targetLanguage: String

    public init(translate: Bool, targetLanguage: String) {
        self.translate = translate
        self.targetLanguage = targetLanguage
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        translate = try container.decodeIfPresent(Bool.self, forKey: .translate) ?? false
        targetLanguage = try container.decodeIfPresent(String.self, forKey: .targetLanguage) ?? "zh-Hans"
    }
}

/// 字幕浮窗的两路语言与翻译开关。
public struct SubtitleSettings: Codable, Sendable, Equatable {
    public var other: SubtitleChannelSettings
    public var me: SubtitleChannelSettings
    public var fontSize: Double
    public var opacity: Double

    public init(
        other: SubtitleChannelSettings = .init(translate: true, targetLanguage: "zh-Hans"),
        me: SubtitleChannelSettings = .init(translate: false, targetLanguage: "en"),
        fontSize: Double = 20,
        opacity: Double = 0.82
    ) {
        self.other = other
        self.me = me
        self.fontSize = fontSize
        self.opacity = opacity
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        other = try container.decodeIfPresent(SubtitleChannelSettings.self, forKey: .other)
            ?? .init(translate: true, targetLanguage: "zh-Hans")
        me = try container.decodeIfPresent(SubtitleChannelSettings.self, forKey: .me)
            ?? .init(translate: false, targetLanguage: "en")
        fontSize = try container.decodeIfPresent(Double.self, forKey: .fontSize) ?? 20
        opacity = try container.decodeIfPresent(Double.self, forKey: .opacity) ?? 0.82
    }

}

public struct AudioSessionSettings: Codable, Sendable, Equatable {
    public var captureSystemAudio: Bool
    public var captureMicrophone: Bool
    public var recordMeetings: Bool
    public var otherLanguage: String
    public var meLanguage: String

    public init(
        captureSystemAudio: Bool = true,
        captureMicrophone: Bool = true,
        recordMeetings: Bool = false,
        otherLanguage: String = "en",
        meLanguage: String = "zh-Hans"
    ) {
        self.captureSystemAudio = captureSystemAudio
        self.captureMicrophone = captureMicrophone
        self.recordMeetings = recordMeetings
        self.otherLanguage = otherLanguage
        self.meLanguage = meLanguage
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        captureSystemAudio = try container.decodeIfPresent(Bool.self, forKey: .captureSystemAudio) ?? true
        captureMicrophone = try container.decodeIfPresent(Bool.self, forKey: .captureMicrophone) ?? true
        recordMeetings = try container.decodeIfPresent(Bool.self, forKey: .recordMeetings) ?? false
        otherLanguage = try container.decodeIfPresent(String.self, forKey: .otherLanguage) ?? "en"
        meLanguage = try container.decodeIfPresent(String.self, forKey: .meLanguage) ?? "zh-Hans"
    }
}

public struct AppSettings: Codable, Sendable, Equatable {
    public var residentModelID: String?
    public var scenes: [String: SceneSettings]
    public var services: [String: ServiceSettings]
    public var general: GeneralSettings
    public var modelContextOverrides: [String: Int]
    public var scanRoots: [String]
    public var subtitle: SubtitleSettings
    public var audioSession: AudioSessionSettings

    public init(
        residentModelID: String? = nil,
        scenes: [String: SceneSettings] = [:],
        services: [String: ServiceSettings] = [:],
        general: GeneralSettings = GeneralSettings(),
        modelContextOverrides: [String: Int] = [:],
        scanRoots: [String] = AppSettings.defaultScanRoots(),
        subtitle: SubtitleSettings = SubtitleSettings(),
        audioSession: AudioSessionSettings = AudioSessionSettings()
    ) {
        self.residentModelID = residentModelID
        self.scenes = scenes
        self.services = services
        self.general = general
        self.modelContextOverrides = modelContextOverrides
        self.scanRoots = scanRoots
        self.subtitle = subtitle
        self.audioSession = audioSession
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        residentModelID = try container.decodeIfPresent(String.self, forKey: .residentModelID)
        scenes = try container.decodeIfPresent([String: SceneSettings].self, forKey: .scenes) ?? [:]
        services = try container.decodeIfPresent([String: ServiceSettings].self, forKey: .services) ?? [:]
        general = try container.decodeIfPresent(GeneralSettings.self, forKey: .general) ?? GeneralSettings()
        modelContextOverrides = try container.decodeIfPresent([String: Int].self, forKey: .modelContextOverrides) ?? [:]
        scanRoots = try container.decodeIfPresent([String].self, forKey: .scanRoots) ?? AppSettings.defaultScanRoots()
        subtitle = try container.decodeIfPresent(SubtitleSettings.self, forKey: .subtitle) ?? SubtitleSettings()
        audioSession = try container.decodeIfPresent(AudioSessionSettings.self, forKey: .audioSession) ?? AudioSessionSettings()
    }

    public static func defaultScanRoots() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            home + "/mlx-models",
            home + "/.cache/huggingface/hub",
            home + "/.lmstudio/models"
        ]
    }

    public func scene(_ id: SceneID) -> SceneSettings {
        scenes[id.rawValue] ?? SceneSettings(parameters: id.defaultParameters)
    }

    public mutating func setScene(_ scene: SceneSettings, for id: SceneID) {
        scenes[id.rawValue] = scene
    }

    public func service(for modelID: String) -> ServiceSettings {
        services[modelID] ?? ServiceSettings()
    }

    public mutating func setService(_ service: ServiceSettings, for modelID: String) {
        services[modelID] = service
    }

    /// 场景实际使用的模型 id；返回 nil 表示应使用常驻模型。
    public func specificModelID(for sceneID: SceneID) -> String? {
        let sceneSettings = scene(sceneID)
        return sceneSettings.useResidentModel ? nil : sceneSettings.modelID
    }

    /// 模型上下文长度覆盖值。
    public func contextLengthOverride(for modelID: String) -> Int? {
        modelContextOverrides[modelID]
    }
}
