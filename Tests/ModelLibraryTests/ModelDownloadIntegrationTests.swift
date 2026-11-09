import Foundation
import Testing
@testable import ModelLibrary

/// 真实下载一个带子目录的仓库，验证目录条目不会被当成文件去下（会 404）。
/// LINGOLENS_MODEL_DL_TEST=1 swift test --filter ModelDownloadIntegrationTests
@Suite("模型下载集成")
struct ModelDownloadIntegrationTests {
    @Test(
        "带子目录的仓库能正常开始下载",
        .enabled(if: ProcessInfo.processInfo.environment["LINGOLENS_MODEL_DL_TEST"] != nil),
        .timeLimit(.minutes(3))
    )
    func downloadsRepoWithDirectories() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LingoDL-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let downloader = HFDownloader(modelsDirectory: directory)
        let probe = DownloadProbe()

        let task = Task {
            _ = try? await downloader.download(
                repoID: "prism-ml/Ternary-Bonsai-2-4B-mlx-2bit",
                source: .modelScope
            ) { progress in
                probe.record(progress)
            }
        }

        // 等到第二个文件就说明第一个文件真的下完了（不是秒失败）。
        for _ in 0..<200 where (probe.latest?.fileIndex ?? -1) < 1 {
            try? await Task.sleep(for: .milliseconds(200))
        }
        task.cancel()
        _ = await task.value

        let latest = probe.latest
        print("[dl] fileIndex=\(latest?.fileIndex ?? -1) file=\(latest?.currentFile ?? "nil") downloaded=\(latest?.fileBytesDownloaded ?? 0)")
        #expect(latest != nil)
        #expect((latest?.fileIndex ?? -1) >= 0)

        // 目录条目不应该出现在下载列表里。
        let names = probe.seenFiles
        print("[dl] 前几个文件: \(names.prefix(6))")
        #expect(!names.contains("mtp"))
        #expect(!names.contains("runtime"))
    }
}

private final class DownloadProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var value: DownloadProgress?
    private var files: [String] = []

    var latest: DownloadProgress? {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    var seenFiles: [String] {
        lock.lock(); defer { lock.unlock() }
        return files
    }

    func record(_ progress: DownloadProgress) {
        lock.lock(); defer { lock.unlock() }
        value = progress
        if files.last != progress.currentFile {
            files.append(progress.currentFile)
        }
    }
}
