import Foundation

/// 面向本地 mlx_vlm server 的流式客户端。
public struct LocalLLMClient: Sendable {
    private let http: any HTTPStreaming

    public init(http: any HTTPStreaming = URLSessionHTTPStreaming()) {
        self.http = http
    }

    public func streamChat(baseURL: URL, request: ChatRequest) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await perform(baseURL: baseURL, request: request, continuation: continuation)
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

    private func perform(
        baseURL: URL,
        request: ChatRequest,
        continuation: AsyncThrowingStream<ChatStreamEvent, Error>.Continuation
    ) async throws {
        let base = baseURL.absoluteString.hasSuffix("/") ? baseURL.absoluteString : baseURL.absoluteString + "/"
        guard let root = URL(string: base),
              let url = URL(string: "v1/chat/completions", relativeTo: root)
        else {
            throw ChatError.invalidBaseURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        urlRequest.timeoutInterval = 600
        urlRequest.httpBody = try Self.encodeBody(request)

        let clock = ContinuousClock()
        let start = clock.now
        var firstTokenAt: ContinuousClock.Instant?

        let response = try await http.stream(urlRequest)
        guard (200..<300).contains(response.statusCode) else {
            var body = ""
            for try await data in response.body {
                body += String(decoding: data, as: UTF8.self)
                if body.count > 2000 { break }
            }
            throw ChatError.httpStatus(code: response.statusCode, body: body)
        }

        var parser = SSEParser()
        var usage: ChatUsage?

        func handle(_ events: [SSEEvent]) {
            for event in events {
                guard event.data != "[DONE]" else { continue }
                guard let data = event.data.data(using: .utf8),
                      let chunk = try? JSONDecoder().decode(ChatCompletionChunk.self, from: data)
                else { continue }
                if let delta = chunk.choices.first?.delta?.content, !delta.isEmpty {
                    if firstTokenAt == nil {
                        firstTokenAt = clock.now
                    }
                    continuation.yield(.delta(delta))
                }
                if let chunkUsage = chunk.usage {
                    usage = chunkUsage
                }
            }
        }

        for try await data in response.body {
            try Task.checkCancellation()
            let text = String(decoding: data, as: UTF8.self)
            handle(parser.consume(text))
        }
        handle(parser.finish())

        let end = clock.now
        let duration = Self.seconds(start.duration(to: end))
        let timeToFirstToken = firstTokenAt.map { Self.seconds(start.duration(to: $0)) }
        continuation.yield(.finished(ChatMetrics(timeToFirstToken: timeToFirstToken, duration: duration, usage: usage)))
    }

    public static func encodeBody(_ request: ChatRequest) throws -> Data {
        var object: [String: Any] = [
            "model": request.model,
            "messages": request.messages.map { ["role": $0.role.rawValue, "content": $0.content] },
            "stream": true,
            "temperature": request.parameters.temperature,
            "top_p": request.parameters.topP,
            "max_tokens": request.parameters.maxTokens,
            "repetition_penalty": request.parameters.repetitionPenalty,
            "chat_template_kwargs": ["enable_thinking": request.parameters.thinking]
        ]
        if request.parameters.thinking {
            object["chat_template_kwargs"] = ["enable_thinking": true]
        }
        do {
            return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        } catch {
            throw ChatError.encodingFailed(error.localizedDescription)
        }
    }

    private static func seconds(_ duration: Duration) -> TimeInterval {
        let components = duration.components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
