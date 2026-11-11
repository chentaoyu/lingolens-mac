import Foundation
import Testing
@testable import ModelRuntime

/// 每跨过 10% 打一行，避免刷屏；用引用类型绕过并发捕获限制。
final class ProgressPrinter: @unchecked Sendable {
    private let lock = NSLock()
    private var lastReported = 0

    func report(percent: Int, file: String) {
        lock.lock()
        let shouldPrint = percent >= lastReported + 10
        if shouldPrint { lastReported = percent }
        lock.unlock()
        if shouldPrint {
            print("[download] \(percent)% \(file)")
        }
    }
}

/// 真实从魔搭下载默认语音模型（约 1 GB），默认跳过。
/// LINGOLENS_SPEECH_DOWNLOAD_TEST=1 swift test --filter SpeechModelDownloadIntegrationTests
@Suite("模型下载集成")
struct SpeechModelDownloadIntegrationTests {
    @Test(
        "下载并校验文件",
        .enabled(if: ProcessInfo.processInfo.environment["LINGOLENS_SPEECH_DOWNLOAD_TEST"] != nil),
        .timeLimit(.minutes(30))
    )
    func downloads() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LingoDownload-\(UUID().uuidString)", isDirectory: true)
        let paths = RuntimePaths(
            appSupportDirectory: root.appendingPathComponent("support", isDirectory: true),
            logsDirectory: root.appendingPathComponent("logs", isDirectory: true)
        )
        try paths.prepare()
        defer { try? FileManager.default.removeItem(at: root) }

        let installer = SpeechModelInstaller(paths: paths)
        #expect(!installer.isInstalled)

        let started = Date()
        let counter = ProgressPrinter()
        try await installer.install { progress in
            counter.report(percent: Int(progress.fraction * 100), file: progress.currentFile)
        }
        print("[download] 用时 \(Int(Date().timeIntervalSince(started)))s")

        #expect(installer.isInstalled)
        for file in installer.model.files {
            let url = installer.directory.appendingPathComponent(file.name)
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? Int64 ?? 0
            #expect(abs(size - file.expectedSize) <= max(file.expectedSize / 100, 1024),
                    "\(file.name) 实际 \(size) 预期 \(file.expectedSize)")
        }
    }
}
