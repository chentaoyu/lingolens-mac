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

    public func translate(
        text: String,
        scene: SceneID = .selectionTranslation
    ) -> AsyncThrowingStream<TranslationEvent, Error> {
        let preferred = settingsStore.settings.general.targetLanguage
        let target = TranslationDirection.resolvedTargetLanguage(
            preferred: preferred,
            sourceText: text
        )
        let messages = TranslationPrompt.messages(text: text, targetLanguage: target)
        return chat.stream(scene: scene, messages: messages)
    }
}
