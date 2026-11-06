import Foundation

public enum ChatRole: String, Codable, Sendable {
    case system
    case user
    case assistant
}

public struct ChatMessage: Codable, Sendable, Equatable {
    public let role: ChatRole
    public let content: String

    public init(role: ChatRole, content: String) {
        self.role = role
        self.content = content
    }

    public static func system(_ content: String) -> ChatMessage { .init(role: .system, content: content) }
    public static func user(_ content: String) -> ChatMessage { .init(role: .user, content: content) }
    public static func assistant(_ content: String) -> ChatMessage { .init(role: .assistant, content: content) }
}

/// 生成参数。未在 JSON 中出现的字段使用场景默认值。
public struct GenerationParameters: Codable, Sendable, Equatable {
    public var temperature: Double
    public var topP: Double
    public var maxTokens: Int
    public var repetitionPenalty: Double
    public var thinking: Bool

    public init(
        temperature: Double = 0.2,
        topP: Double = 0.9,
        maxTokens: Int = 1024,
        repetitionPenalty: Double = 1.0,
        thinking: Bool = false
    ) {
        self.temperature = temperature
        self.topP = topP
        self.maxTokens = maxTokens
        self.repetitionPenalty = repetitionPenalty
        self.thinking = thinking
    }

    private enum CodingKeys: String, CodingKey {
        case temperature, topP, maxTokens, repetitionPenalty, thinking
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = GenerationParameters()
        temperature = try container.decodeIfPresent(Double.self, forKey: .temperature) ?? fallback.temperature
        topP = try container.decodeIfPresent(Double.self, forKey: .topP) ?? fallback.topP
        maxTokens = try container.decodeIfPresent(Int.self, forKey: .maxTokens) ?? fallback.maxTokens
        repetitionPenalty = try container.decodeIfPresent(Double.self, forKey: .repetitionPenalty) ?? fallback.repetitionPenalty
        thinking = try container.decodeIfPresent(Bool.self, forKey: .thinking) ?? fallback.thinking
    }

    // 场景默认参数（见设计文档 6.2）。
    public static let selectionTranslation = GenerationParameters(
        temperature: 0.2, topP: 0.9, maxTokens: 1024, repetitionPenalty: 1.0, thinking: false
    )

    public static let liveSubtitle = GenerationParameters(
        temperature: 0, topP: 1.0, maxTokens: 256, repetitionPenalty: 1.0, thinking: false
    )

    public static let meetingMinutes = GenerationParameters(
        temperature: 0.3, topP: 0.9, maxTokens: 4096, repetitionPenalty: 1.0, thinking: false
    )
}

public struct ChatRequest: Sendable, Equatable {
    public var model: String
    public var messages: [ChatMessage]
    public var parameters: GenerationParameters

    public init(model: String, messages: [ChatMessage], parameters: GenerationParameters) {
        self.model = model
        self.messages = messages
        self.parameters = parameters
    }
}

public struct ChatUsage: Codable, Sendable, Equatable {
    public var promptTokens: Int?
    public var completionTokens: Int?
    public var totalTokens: Int?

    public init(promptTokens: Int? = nil, completionTokens: Int? = nil, totalTokens: Int? = nil) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
    }

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}

public struct ChatMetrics: Sendable, Equatable {
    public var timeToFirstToken: TimeInterval?
    public var duration: TimeInterval
    public var usage: ChatUsage?
    /// 收到的非空增量片段数；server 不返回 usage 时用来估算生成速度。
    public var deltaCount: Int

    public init(timeToFirstToken: TimeInterval?, duration: TimeInterval, usage: ChatUsage?, deltaCount: Int = 0) {
        self.timeToFirstToken = timeToFirstToken
        self.duration = duration
        self.usage = usage
        self.deltaCount = deltaCount
    }

    public var tokensPerSecond: Double? {
        if let tokens = usage?.completionTokens, tokens > 0, duration > 0 {
            return Double(tokens) / duration
        }
        // mlx_vlm 流式输出大致一个片段一个 token，只统计首字之后的生成时间。
        let generation = duration - (timeToFirstToken ?? 0)
        guard deltaCount > 1, generation > 0 else { return nil }
        return Double(deltaCount - 1) / generation
    }
}

public enum ChatStreamEvent: Sendable, Equatable {
    case delta(String)
    case finished(ChatMetrics)
}

public enum ChatError: Error, LocalizedError, Equatable, Sendable {
    case invalidBaseURL
    case httpStatus(code: Int, body: String)
    case encodingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "模型服务地址无效。"
        case let .httpStatus(code, body):
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            return "模型服务返回错误（HTTP \(code)）：\(trimmed.isEmpty ? "无响应内容" : String(trimmed.prefix(400)))"
        case let .encodingFailed(message):
            return "请求编码失败：\(message)"
        }
    }
}

struct ChatCompletionChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            let content: String?
            let reasoningContent: String?

            enum CodingKeys: String, CodingKey {
                case content
                case reasoningContent = "reasoning_content"
            }
        }

        let delta: Delta?
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case delta
            case finishReason = "finish_reason"
        }
    }

    let choices: [Choice]
    let usage: ChatUsage?
}
