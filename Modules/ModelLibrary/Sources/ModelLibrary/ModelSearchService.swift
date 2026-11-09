import Foundation

/// 模型仓库里的一个可下载条目（目前来自魔搭）。
public struct RemoteModel: Sendable, Identifiable, Equatable {
    /// 形如 mlx-community/Qwen3.5-4B-MLX-4bit
    public let repositoryID: String
    public let downloads: Int
    public let stars: Int
    public let sizeBytes: Int64?

    public var id: String { repositoryID }

    public var namespace: String {
        repositoryID.split(separator: "/").first.map(String.init) ?? ""
    }

    public var name: String {
        let parts = repositoryID.split(separator: "/")
        return parts.count > 1 ? String(parts[1]) : repositoryID
    }

    /// 名字里带 mlx 的更可能是本应用能加载的权重。
    public var looksLikeMLX: Bool {
        repositoryID.lowercased().contains("mlx")
    }

    public init(repositoryID: String, downloads: Int = 0, stars: Int = 0, sizeBytes: Int64? = nil) {
        self.repositoryID = repositoryID
        self.downloads = downloads
        self.stars = stars
        self.sizeBytes = sizeBytes
    }
}

public enum ModelSearchError: Error, LocalizedError {
    case badResponse(Int)
    case decodeFailed

    public var errorDescription: String? {
        switch self {
        case let .badResponse(code): return "搜索模型失败（HTTP \(code)）"
        case .decodeFailed: return "无法解析模型搜索结果"
        }
    }
}

/// 从魔搭搜索模型。
///
/// 魔搭的搜索接口是 PUT /api/v1/dolphin/models，请求体带分页与关键词；
/// 返回里 Path 是命名空间、Name 是仓库名，拼起来才是完整 repo id。
public actor ModelSearchService {
    private struct SearchRequest: Encodable {
        let PageSize: Int
        let PageNumber: Int
        let Name: String
        let SortBy: String
    }

    private struct SearchResponse: Decodable {
        struct DataBlock: Decodable {
            struct ModelBlock: Decodable {
                struct Item: Decodable {
                    let Name: String
                    let Path: String
                    let Downloads: Int?
                    let Stars: Int?
                    let StorageSize: Int64?
                }
                let Models: [Item]
            }
            let Model: ModelBlock?
        }
        let Code: Int
        let Data: DataBlock?
    }

    private let session: URLSession
    private let endpoint = URL(string: "https://www.modelscope.cn/api/v1/dolphin/models")!

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// 关键词搜索，按页取。mlxOnly 为 true 时只保留名字带 mlx 的条目。
    ///
    /// 注意：服务端过滤发生在解析之后，所以一页可能因为被过滤而少于 pageSize，
    /// 判断「还有没有下一页」要用原始返回条数，不能用过滤后的数量。
    public func search(
        _ keyword: String,
        page: Int = 1,
        pageSize: Int = 10,
        mlxOnly: Bool = true
    ) async throws -> ModelSearchPage {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "PUT"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // 魔搭按名字做多词匹配；不带 mlx 的查询前排几乎都是非 MLX 权重，
        // 补一个 mlx 关键词能直接把 MLX 版本顶上来（实测 whisper → whisper mlx 有效）。
        var terms = keyword
        if mlxOnly, !keyword.lowercased().contains("mlx") {
            terms = keyword + " mlx"
        }

        request.httpBody = try JSONEncoder().encode(
            SearchRequest(
                PageSize: max(1, min(pageSize, 100)),
                PageNumber: max(1, page),
                Name: terms,
                SortBy: "Default"
            )
        )

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ModelSearchError.badResponse((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        guard let payload = try? JSONDecoder().decode(SearchResponse.self, from: data),
              let items = payload.Data?.Model?.Models
        else {
            throw ModelSearchError.decodeFailed
        }

        let models = items.compactMap { item -> RemoteModel? in
            let id = item.Path.isEmpty ? item.Name : item.Path + "/" + item.Name
            guard !id.contains(".."), id.count < 200 else { return nil }
            let model = RemoteModel(
                repositoryID: id,
                downloads: item.Downloads ?? 0,
                stars: item.Stars ?? 0,
                sizeBytes: item.StorageSize
            )
            if mlxOnly, !model.looksLikeMLX { return nil }
            return model
        }

        return ModelSearchPage(
            models: models,
            page: max(1, page),
            hasMore: items.count >= max(1, pageSize)
        )
    }
}

/// 一页搜索结果。
public struct ModelSearchPage: Sendable, Equatable {
    public let models: [RemoteModel]
    public let page: Int
    /// 服务端这一页是否满员；满员才可能还有下一页。
    public let hasMore: Bool

    public init(models: [RemoteModel], page: Int, hasMore: Bool) {
        self.models = models
        self.page = page
        self.hasMore = hasMore
    }
}
