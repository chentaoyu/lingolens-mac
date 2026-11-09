import Foundation
import ModelLibrary

/// 「下载模型」面板的搜索与分页状态。
///
/// 滚动到底部自动加载下一页；每次换关键词都从头开始，且只认最后一次查询的结果，
/// 避免慢请求覆盖新结果。
@MainActor
final class ModelSearchViewModel: ObservableObject {
    /// 每页条数，与需求一致。
    static let pageSize = 10

    @Published var query = ""
    @Published private(set) var models: [RemoteModel] = []
    @Published private(set) var selectedID: String?
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasMore = false
    @Published private(set) var errorMessage: String?
    /// 搜过一次之后才显示「没有结果」，避免刚打开面板就报空。
    @Published private(set) var didSearch = false

    private let service = ModelSearchService()
    private var page = 0
    private var currentTask: Task<Void, Never>?
    /// 每次查询的代号，慢请求回来时用它判断是不是过期结果。
    private var generation = 0

    func search() {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else {
            reset()
            return
        }

        generation &+= 1
        let token = generation
        currentTask?.cancel()
        page = 0
        models = []
        hasMore = false
        errorMessage = nil
        isLoading = true
        didSearch = true

        currentTask = Task { [weak self] in
            await self?.load(page: 1, keyword: keyword, token: token, isFirstPage: true)
        }
    }

    /// 滚到列表底部时调用；已经在加载或没有下一页时是空操作。
    func loadMoreIfNeeded(current model: RemoteModel) {
        guard model.id == models.last?.id else { return }
        loadMore()
    }

    func loadMore() {
        guard hasMore, !isLoading, !isLoadingMore else { return }
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return }

        let token = generation
        isLoadingMore = true
        currentTask = Task { [weak self] in
            await self?.load(page: self.map { $0.page + 1 } ?? 1, keyword: keyword, token: token, isFirstPage: false)
        }
    }

    func select(_ model: RemoteModel) {
        selectedID = model.id
    }

    func reset() {
        generation &+= 1
        currentTask?.cancel()
        currentTask = nil
        page = 0
        models = []
        hasMore = false
        isLoading = false
        isLoadingMore = false
        errorMessage = nil
        didSearch = false
    }

    // MARK: - 私有

    private func load(page nextPage: Int, keyword: String, token: Int, isFirstPage: Bool) async {
        do {
            let result = try await service.search(keyword, page: nextPage, pageSize: Self.pageSize)
            guard token == generation else { return }
            page = result.page
            let existing = Set(models.map(\.id))
            models += result.models.filter { !existing.contains($0.id) }
            hasMore = result.hasMore
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard token == generation else { return }
            errorMessage = error.localizedDescription
            if isFirstPage { hasMore = false }
        }
        if token == generation {
            isLoading = false
            isLoadingMore = false
        }
    }
}
