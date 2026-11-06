import Foundation
import LLMClient
import ModelLibrary
import ModelRuntime
import SceneChat
import Settings

public typealias ModelResolutionError = SceneChatError
public typealias TranslationEvent = SceneChatEvent

/// 划词翻译：组装提示词后交给通用场景服务。
@MainActor
public final class TranslationService {
    private let chat: SceneChatService
    private let settingsStore: SettingsStore

    public init(chat: SceneChatService, settingsStore: SettingsStore) {
        self.chat = chat
        self.settingsStore = settingsStore
    }

    public convenience init(
        client: LocalLLMClient,
        pool: ServerPool,
        settingsStore: SettingsStore,
        catalog: ModelCatalog
    ) {
        self.init(
            chat: SceneChatService(
                client: client,
                pool: pool,
                settingsStore: settingsStore,
                catalog: catalog
            ),
            settingsStore: settingsStore
        )
    }

    /// 未指定目标语言时，按设置的目标语言并处理“原文即目标语言”的情况。
    public func resolvedTargetLanguage(for text: String) -> String {
        TranslationDirection.resolvedTargetLanguage(
            preferred: settingsStore.settings.general.targetLanguage,
            sourceText: text
        )
    }

    public func translate(
        text: String,
        targetLanguage: String? = nil,
        scene: SceneID = .selectionTranslation
    ) -> AsyncThrowingStream<TranslationEvent, Error> {
        let target = targetLanguage ?? resolvedTargetLanguage(for: text)
        let messages = TranslationPrompt.messages(text: text, targetLanguage: target)
        return chat.stream(scene: scene, messages: messages)
    }
}
