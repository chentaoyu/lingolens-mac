import AudioCapture
import Foundation
import LLMClient
import ModelLibrary
import ModelRuntime
import SceneChat
import Settings

public enum MinutesEvent: Sendable, Equatable {
    case phase(String)
    case delta(String)
    case finished
}

/// 生成会议纪要；长会议先分段提炼，再合并为最终纪要。
@MainActor
public final class MinutesGenerator {
    private let chat: SceneChatService
    private let settingsStore: SettingsStore

    public init(chat: SceneChatService, settingsStore: SettingsStore) {
        self.chat = chat
        self.settingsStore = settingsStore
    }

    public func generate(
        meeting: MeetingDetail,
        template: MinutesTemplate,
        targetLanguage: String = "简体中文",
        modelID: String? = nil
    ) -> AsyncThrowingStream<MinutesEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                do {
                    let (model, _) = try await self.chat.resolveModel(for: .meetingMinutes, modelID: modelID)
                    let contextLength = self.contextLength(for: model)
                    let entries = meeting.entries

                    var sourceText: String
                    if MeetingSegmenter.needsSegmentation(entries, contextLength: contextLength) {
                        let budget = max(1024, contextLength / 3)
                        let chunks = MeetingSegmenter.segments(entries, tokenBudget: budget)
                        continuation.yield(.phase("长会议：分 \(chunks.count) 段提炼要点…"))

                        var summaries: [String] = []
                        for (index, chunk) in chunks.enumerated() {
                            try Task.checkCancellation()
                            continuation.yield(.phase("正在提炼第 \(index + 1)/\(chunks.count) 段…"))
                            let summary = try await self.summarize(chunk: chunk, meeting: meeting, modelID: model.id)
                            summaries.append("### 片段 \(index + 1)\n\(summary)")
                        }
                        sourceText = summaries.joined(separator: "\n\n")
                    } else {
                        sourceText = Self.transcriptText(entries)
                    }

                    continuation.yield(.phase("生成最终纪要…"))
                    let messages = MinutesPrompt.messages(
                        template: template,
                        source: sourceText,
                        targetLanguage: targetLanguage
                    )

                    for try await event in self.chat.stream(
                        scene: .meetingMinutes,
                        messages: messages,
                        modelID: model.id
                    ) {
                        if case let .delta(delta) = event {
                            continuation.yield(.delta(delta))
                        }
                    }
                    continuation.yield(.finished)
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func summarize(chunk: [TranscriptEntry], meeting: MeetingDetail, modelID: String) async throws -> String {
        let messages = MinutesPrompt.segmentMessages(
            transcript: Self.transcriptText(chunk)
        )
        var summary = ""
        for try await event in chat.stream(scene: .meetingMinutes, messages: messages, modelID: modelID) {
            if case let .delta(delta) = event {
                summary += delta
            }
        }
        return summary
    }

    private func contextLength(for model: ModelRef) -> Int {
        if let override = settingsStore.settings.modelContextOverrides[model.id] {
            return max(2048, override)
        }
        if let config = ModelInspector.readConfig(model.directory),
           let length = ModelInspector.contextLength(config: config) {
            return max(2048, length)
        }
        return 32_768
    }

    public static func transcriptText(_ entries: [TranscriptEntry]) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return entries.map { entry in
            let time = formatter.string(from: entry.time)
            return "[\(time)] \(entry.speaker.displayName)：\(entry.text)"
        }.joined(separator: "\n")
    }

}

public enum MinutesPrompt {
    public static func messages(
        template: MinutesTemplate,
        source: String,
        targetLanguage: String
    ) -> [ChatMessage] {
        let system = """
        \(template.prompt)

        输出语言：\(targetLanguage)。只输出 Markdown 纪要，不要输出思考过程或额外说明。
        """
        let user = "以下是会议转写内容：\n\n\(source)"
        return [.system(system), .user(user)]
    }

    public static func segmentMessages(transcript: String) -> [ChatMessage] {
        let system = """
        你是会议助理。请提炼以下会议转写片段的要点，保留：讨论主题、结论、行动项、待定问题。
        用简洁中文分条输出，不要编造，不要输出与片段无关的内容。
        """
        let user = "转写片段：\n\n\(transcript)"
        return [.system(system), .user(user)]
    }
}
