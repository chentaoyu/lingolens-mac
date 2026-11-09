import Foundation
import Testing
@testable import ModelLibrary

/// 真实访问魔搭列文件，验证下载源可用。默认跳过（只列文件，不下完）。
/// LINGOLENS_MODEL_LIST_TEST=1 swift test --filter ModelSourceIntegrationTests
@Suite("模型下载源集成")
struct ModelSourceIntegrationTests {
    @Test(
        "魔搭能列出推荐模型的文件",
        .enabled(if: ProcessInfo.processInfo.environment["LINGOLENS_MODEL_LIST_TEST"] != nil),
        .timeLimit(.minutes(3))
    )
    func listsFromModelScope() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LingoList-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let downloader = HFDownloader(modelsDirectory: directory)
        let probe = FileListProbe()

        // 拿到第一个文件的进度就说明列表解析成功了，随后取消，不真的下 3 GB。
        let task = Task {
            _ = try? await downloader.download(
                repoID: HFDownloader.recommendedRepositoryID,
                source: .modelScope
            ) { progress in
                probe.record(progress)
            }
        }

        for _ in 0..<150 where probe.first == nil {
            try? await Task.sleep(for: .milliseconds(200))
        }
        task.cancel()
        _ = await task.value

        let first = probe.first
        print("[list] first=\(first?.currentFile ?? "nil") fileCount=\(first?.fileCount ?? -1)")
        #expect(first != nil)
        #expect((first?.fileCount ?? 0) > 0)
        #expect(first?.currentFile.isEmpty == false)
    }
}

private final class FileListProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var value: DownloadProgress?

    var first: DownloadProgress? {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    func record(_ progress: DownloadProgress) {
        lock.lock(); defer { lock.unlock() }
        if value == nil { value = progress }
    }
}
