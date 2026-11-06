import AudioCapture
import Foundation
import LLMClient
import SceneChat
import Settings
import Transcriber

/// 什么时候值得翻译：开关打开，且这句话的语言不是目标语言。
public enum SubtitleTranslationPolicy {
    public static func shouldTranslate(
        channel: SubtitleChannelSettings,
        targetLanguage: String,
        sourceLanguage: String?
    ) -> Bool {
        guard channel.translate else { return false }
        guard let sourceLanguage, !sourceLanguage.isEmpty else { return true }
        return !SubtitleLanguage.isSame(sourceLanguage, targetLanguage)
    }
}

/// 每路一个翻译队列，按设置决定是否翻译与目标语言。
@MainActor
public final class SubtitleTranslationController {
    private let chat: SceneChatService
    private let settingsStore: SettingsStore
    private let store: SubtitleStore
    private var workers: [AudioChannel: ChannelWorker] = [:]

    /// 翻译完成时回调（行 id, 译文），用于同步会议记录。
    public var onTranslation: ((UUID, String) -> Void)?

    public init(chat: SceneChatService, settingsStore: SettingsStore, store: SubtitleStore) {
        self.chat = chat
        self.settingsStore = settingsStore
        self.store = store
    }

    public func enqueue(id: UUID, channel: AudioChannel, text: String, sourceLanguage: String? = nil) {
        let settings = settingsStore.settings.subtitle
        let channelSettings = channel == .me ? settings.me : settings.other
        // 源语言已经等于目标语言时没有翻译的必要（中文会议里「中文译中文」只会白跑模型）。
        guard SubtitleTranslationPolicy.shouldTranslate(
            channel: channelSettings,
            targetLanguage: settings.targetLanguage,
            sourceLanguage: sourceLanguage
        ) else { return }
        worker(for: channel).enqueue(id: id, text: text)
    }

    public func cancelAll() {
        workers.values.forEach { $0.cancel() }
    }

    private func worker(for channel: AudioChannel) -> ChannelWorker {
        if let worker = workers[channel] { return worker }
        let worker = ChannelWorker(
            channel: channel,
            chat: chat,
            settingsStore: settingsStore,
            store: store
        )
        worker.onTranslated = { [weak self] id, text in
            self?.onTranslation?(id, text)
        }
        workers[channel] = worker
        return worker
    }

    // MARK: - Per-channel worker

    @MainActor
    private final class ChannelWorker {
        private let channel: AudioChannel
        private let chat: SceneChatService
        private let settingsStore: SettingsStore
        private let store: SubtitleStore

        private var pending: [PendingSubtitle] = []
        private var history: [String] = []
        private var task: Task<Void, Never>?
        var onTranslated: ((UUID, String) -> Void)?

        init(channel: AudioChannel, chat: SceneChatService, settingsStore: SettingsStore, store: SubtitleStore) {
            self.channel = channel
            self.chat = chat
            self.settingsStore = settingsStore
            self.store = store
        }

        func enqueue(id: UUID, text: String) {
            pending.append(PendingSubtitle(id: id, text: text))
            guard task == nil else { return }
            task = Task { @MainActor [weak self] in
                await self?.process()
            }
        }

        func cancel() {
            task?.cancel()
            task = nil
            pending.removeAll()
        }

        private var channelSettings: SubtitleChannelSettings {
            let subtitle = settingsStore.settings.subtitle
            return channel == .me ? subtitle.me : subtitle.other
        }

        /// 目标语言是全局设置：所有字幕都译成这一种，源语言相同则跳过。
        private var targetLanguage: String {
            settingsStore.settings.subtitle.targetLanguage
        }

        private func process() async {
            defer { task = nil }

            while !pending.isEmpty {
                if Task.isCancelled { return }

                let settings = channelSettings
                guard settings.translate else {
                    pending.removeAll()
                    return
                }

                let batches = SubtitleTranslationPlanner.plan(pending: pending, context: history)
                guard let batch = batches.first else { return }
                pending.removeAll { batch.ids.contains($0.id) }

                var output = ""
                do {
                    let messages = SubtitlePrompt.messages(
                        batch: batch,
                        targetLanguage: targetLanguage
                    )
                    var parameters = settingsStore.settings.scene(.liveSubtitle).parameters
                    if batch.ids.count > 1 {
                        parameters.maxTokens = max(
                            parameters.maxTokens,
                            min(2048, 96 * batch.ids.count)
                        )
                    }
                    for try await event in chat.stream(
                        scene: .liveSubtitle,
                        messages: messages,
                        parameters: parameters
                    ) {
                        if case let .delta(delta) = event {
                            output += delta
                        }
                    }
                    let distributed = SubtitleTranslationParser.distribute(output, ids: batch.ids)
                    for (id, text) in distributed {
                        store.setTranslation(lineID: id, text: text)
                        onTranslated?(id, text)
                    }
                    let lines = batch.text
                        .split(separator: "\n", omittingEmptySubsequences: true)
                        .map(String.init)
                    history.append(contentsOf: lines)
                    history = Array(history.suffix(8))
                } catch is CancellationError {
                    return
                } catch {
                    batch.ids.forEach { store.markFailed(lineID: $0) }
                }
            }
        }
    }
}
