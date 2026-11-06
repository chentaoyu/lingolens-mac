import Foundation

public struct StreamingHTTPResponse: Sendable {
    public let statusCode: Int
    public let body: AsyncThrowingStream<Data, Error>

    public init(statusCode: Int, body: AsyncThrowingStream<Data, Error>) {
        self.statusCode = statusCode
        self.body = body
    }
}

public protocol HTTPStreaming: Sendable {
    func stream(_ request: URLRequest) async throws -> StreamingHTTPResponse
}

public struct URLSessionHTTPStreaming: HTTPStreaming {
    public init() {}

    public func stream(_ request: URLRequest) async throws -> StreamingHTTPResponse {
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        let body = AsyncThrowingStream<Data, Error> { continuation in
            let task = Task {
                var buffer = Data()
                buffer.reserveCapacity(4096)
                do {
                    for try await byte in bytes {
                        buffer.append(byte)
                        if buffer.count >= 4096 {
                            continuation.yield(buffer)
                            buffer.removeAll(keepingCapacity: true)
                        }
                    }
                    if !buffer.isEmpty {
                        continuation.yield(buffer)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        return StreamingHTTPResponse(statusCode: statusCode, body: body)
    }
}
