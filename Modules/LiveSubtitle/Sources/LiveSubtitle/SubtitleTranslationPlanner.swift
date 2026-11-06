import Foundation
import LLMClient

public struct PendingSubtitle: Sendable, Equatable {
    public let id: UUID
    public let text: String

    public init(id: UUID, text: String) {
        self.id = id
        self.text = text
    }
}

public struct SubtitleBatch: Sendable, Equatable {
    public let ids: [UUID]
    public let text: String
    public let context: [String]

    public init(ids: [UUID], text: String, context: [String]) {
        self.ids = ids
        self.text = text
        self.context = context
    }
}

/// 单个 final 立即翻译；积压超过阈值时合并成一次请求。
public enum SubtitleTranslationPlanner {
    public static func plan(
        pending: [PendingSubtitle],
        context: [String],
        mergeThreshold: Int = 3
    ) -> [SubtitleBatch] {
        guard !pending.isEmpty else { return [] }

        if pending.count > mergeThreshold {
            return [SubtitleBatch(
                ids: pending.map(\.id),
                text: pending.map(\.text).joined(separator: "\n"),
                context: Array(context.suffix(2))
            )]
        }

        return pending.enumerated().map { index, item in
            let prior = context + pending.prefix(index).map(\.text)
            return SubtitleBatch(
                ids: [item.id],
                text: item.text,
                context: Array(prior.suffix(2))
            )
        }
    }
}

public enum SubtitleTranslationParser {
    /// 合并请求可能返回多行，按行分配给对应字幕；行数对不上时整段放到最后一句。
    public static func distribute(_ translation: String, ids: [UUID]) -> [UUID: String] {
        let trimmed = translation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !ids.isEmpty else { return [:] }
        guard ids.count > 1 else { return [ids[0]: trimmed] }

        let lines = trimmed
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        if lines.count == ids.count {
            return Dictionary(uniqueKeysWithValues: zip(ids, lines))
        }
        return [ids[ids.count - 1]: trimmed]
    }
}

public enum SubtitlePrompt {
    public static func messages(batch: SubtitleBatch, targetLanguage: String) -> [ChatMessage] {
        var content = ""
        if !batch.context.isEmpty {
            content += "前文（仅供理解，不要翻译）：\n"
            content += batch.context.joined(separator: "\n")
            content += "\n\n"
        }
        content += "待翻译：\n"
        content += batch.text
        return [.system(systemMessage(targetLanguage: targetLanguage)), .user(content)]
    }

    public static func systemMessage(targetLanguage: String) -> String {
        """
        你是同声传译引擎，把“待翻译”部分翻译成\(languageName(targetLanguage))。
        只输出译文；如果有多行，每行对应一句，行数保持不变；不要输出原文、解释、引号或编号。
        """
    }

    public static func languageName(_ identifier: String) -> String {
        Locale(identifier: "zh-Hans").localizedString(forIdentifier: identifier) ?? identifier
    }
}
