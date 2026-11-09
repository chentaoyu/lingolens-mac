import Foundation
import Testing
@testable import ModelLibrary

/// 真实访问魔搭搜索接口。默认跳过。
/// LINGOLENS_MODEL_SEARCH_TEST=1 swift test --filter ModelSearchIntegrationTests
@Suite("模型搜索集成")
struct ModelSearchIntegrationTests {
    @Test(
        "分页搜索能取到不同结果",
        .enabled(if: ProcessInfo.processInfo.environment["LINGOLENS_MODEL_SEARCH_TEST"] != nil),
        .timeLimit(.minutes(3))
    )
    func searchesWithPagination() async throws {
        let service = ModelSearchService()

        let first = try await service.search("Qwen3.5-4B-MLX", page: 1, pageSize: 10)
        for model in first.models.prefix(10) {
            print("[search p1] \(model.repositoryID) size=\(model.sizeBytes ?? -1) dl=\(model.downloads)")
        }
        #expect(!first.models.isEmpty)
        #expect(first.page == 1)
        #expect(first.models.contains { $0.repositoryID == HFDownloader.recommendedRepositoryID })

        // 满页才可能有下一页；不满就说明已经到底了。
        if first.hasMore {
            let second = try await service.search("Qwen3.5-4B-MLX", page: 2, pageSize: 10)
            print("[search p2] count=\(second.models.count) hasMore=\(second.hasMore)")
            let overlap = Set(first.models.map(\.id)).intersection(Set(second.models.map(\.id)))
            #expect(overlap.isEmpty)
        }

        // 换关键词要能拿到另一批结果。
        let other = try await service.search("whisper", page: 1, pageSize: 10)
        print("[search whisper] count=\(other.models.count)")
        #expect(other.models.allSatisfy { $0.looksLikeMLX })
    }
}

@Suite("模型搜索结果模型")
struct RemoteModelTests {
    @Test("仓库 id 拆分与 MLX 判定")
    func parsesIdentifier() {
        let model = RemoteModel(repositoryID: "mlx-community/Qwen3.5-4B-MLX-4bit")
        #expect(model.namespace == "mlx-community")
        #expect(model.name == "Qwen3.5-4B-MLX-4bit")
        #expect(model.looksLikeMLX)

        let plain = RemoteModel(repositoryID: "someone/plain-model")
        #expect(!plain.looksLikeMLX)
        #expect(plain.namespace == "someone")
    }

    @Test("没有命名空间时也不崩")
    func handlesBareName() {
        let model = RemoteModel(repositoryID: "onlyname")
        #expect(model.namespace == "onlyname")
        #expect(model.name == "onlyname")
    }
}
