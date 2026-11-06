import Foundation
import Testing
@testable import LLMClient

private struct MockHTTP: HTTPStreaming {
    let status: Int
    let chunks: [String]

    func stream(_ request: URLRequest) async throws -> StreamingHTTPResponse {
        let body = AsyncThrowingStream<Data, Error> { continuation in
            for chunk in chunks {
                continuation.yield(Data(chunk.utf8))
            }
            continuation.finish()
        }
        return StreamingHTTPResponse(statusCode: status, body: body)
    }
}

private func makeRequest(thinking: Bool = false) -> ChatRequest {
    ChatRequest(
        model: "Qwen3.5-4B-MLX-4bit",
        messages: [.system("translate"), .user("hello")],
        parameters: GenerationParameters(
            temperature: 0.2, topP: 0.9, maxTokens: 128, repetitionPenalty: 1.1, thinking: thinking
        )
    )
}

@Suite("本地 LLM 客户端")
struct LocalLLMClientTests {
    @Test("解析流式增量与 usage")
    func streamingDeltas() async throws {
        let chunks = [
            "data: {\"choices\":[{\"delta\":{\"content\":\"你\"}}]}\n\n",
            "data: {\"choices\":[{\"delta\":{\"content\":\"好\"}}]}\n\n",
            "data: {\"choices\":[],\"usage\":{\"prompt_tokens\":3,\"completion_tokens\":2,\"total_tokens\":5}}\n\n",
            "data: [DONE]\n\n"
        ]
        let client = LocalLLMClient(http: MockHTTP(status: 200, chunks: chunks))

        var deltas: [String] = []
        var metrics: ChatMetrics?
        for try await event in client.streamChat(
            baseURL: URL(string: "http://127.0.0.1:1234")!,
            request: makeRequest()
        ) {
            switch event {
            case let .delta(text): deltas.append(text)
            case let .finished(value): metrics = value
            }
        }

        #expect(deltas == ["你", "好"])
        #expect(metrics?.usage?.completionTokens == 2)
        #expect(metrics?.duration ?? -1 >= 0)
    }

    @Test("非 2xx 抛出 HTTP 错误")
    func httpError() async {
        let client = LocalLLMClient(http: MockHTTP(status: 500, chunks: ["boom"]))
        do {
            for try await _ in client.streamChat(
                baseURL: URL(string: "http://127.0.0.1:1234")!,
                request: makeRequest()
            ) {}
            Issue.record("应当抛出错误")
        } catch let error as ChatError {
            #expect(error == .httpStatus(code: 500, body: "boom"))
        } catch {
            Issue.record("错误的类型：\(error)")
        }
    }

    @Test("请求体关闭 thinking 时带 chat_template_kwargs")
    func requestBody() throws {
        let data = try LocalLLMClient.encodeBody(makeRequest(thinking: false))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["stream"] as? Bool == true)
        #expect(object["temperature"] as? Double == 0.2)
        #expect(object["max_tokens"] as? Int == 128)
        #expect((object["messages"] as? [[String: Any]])?.count == 2)
        let kwargs = try #require(object["chat_template_kwargs"] as? [String: Any])
        #expect(kwargs["enable_thinking"] as? Bool == false)
    }

    @Test("thinking 打开时 enable_thinking 为 true")
    func requestBodyThinking() throws {
        let data = try LocalLLMClient.encodeBody(makeRequest(thinking: true))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let kwargs = try #require(object["chat_template_kwargs"] as? [String: Any])
        #expect(kwargs["enable_thinking"] as? Bool == true)
    }

    @Test("场景默认生成参数符合设计文档")
    func sceneDefaults() {
        #expect(GenerationParameters.selectionTranslation.temperature == 0.2)
        #expect(GenerationParameters.selectionTranslation.maxTokens == 1024)
        #expect(GenerationParameters.liveSubtitle.temperature == 0)
        #expect(GenerationParameters.liveSubtitle.maxTokens == 256)
        #expect(GenerationParameters.meetingMinutes.temperature == 0.3)
        #expect(GenerationParameters.meetingMinutes.maxTokens == 4096)
    }
}
