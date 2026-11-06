import Foundation

public protocol HealthChecking: Sendable {
    func isServerReady(baseURL: URL, timeout: TimeInterval) async -> Bool
    /// 查询 `/v1/models`，返回服务端实际使用的模型标识（请求时必须带上它）。
    func firstModelIdentifier(baseURL: URL) async -> String?
}

public extension HealthChecking {
    func firstModelIdentifier(baseURL: URL) async -> String? { nil }
}

public struct HTTPServerHealthChecker: HealthChecking {
    public init() {}

    public func isServerReady(baseURL: URL, timeout: TimeInterval) async -> Bool {
        guard let url = Self.url(baseURL, path: "v1/models") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.httpMethod = "GET"
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200..<300).contains(http.statusCode)
        } catch {
            return false
        }
    }

    public func firstModelIdentifier(baseURL: URL) async -> String? {
        guard let url = Self.url(baseURL, path: "v1/models") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.httpMethod = "GET"

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode)
        else { return nil }

        struct ModelList: Decodable {
            struct Item: Decodable {
                let id: String
                let loaded: Bool?
            }
            let data: [Item]
        }
        guard let items = try? JSONDecoder().decode(ModelList.self, from: data).data, !items.isEmpty else {
            return nil
        }
        // 优先返回已加载的模型；部分 OpenAI 兼容服务不提供 loaded 字段。
        return items.first(where: { $0.loaded == true })?.id ?? items[0].id
    }

    private static func url(_ baseURL: URL, path: String) -> URL? {
        let base = baseURL.absoluteString.hasSuffix("/") ? baseURL.absoluteString : baseURL.absoluteString + "/"
        guard let root = URL(string: base) else { return nil }
        return URL(string: path, relativeTo: root)
    }
}
