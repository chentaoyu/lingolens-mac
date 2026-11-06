import Foundation
import Testing
@testable import ModelRuntime

/// 真实跑一次安装（会联网下载约 220MB），默认跳过。
///
/// 运行方式：
/// ```
/// LINGOLENS_RUNTIME_INSTALL_TEST=1 swift test --filter 真实安装
/// ```
@Suite("运行时安装集成测试")
struct RuntimeInstallIntegrationTests {
    @Test(
        "真实安装一次 mlx-vlm 并观察进度",
        .enabled(if: ProcessInfo.processInfo.environment["LINGOLENS_RUNTIME_INSTALL_TEST"] != nil),
        .timeLimit(.minutes(20))
    )
    func realInstall() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LingoRealInstall-\(UUID().uuidString)", isDirectory: true)
        let paths = RuntimePaths(
            appSupportDirectory: root.appendingPathComponent("support", isDirectory: true),
            logsDirectory: root.appendingPathComponent("logs", isDirectory: true)
        )
        try paths.prepare()
        defer { try? FileManager.default.removeItem(at: root) }

        let environment = PythonEnvironment(
            paths: paths,
            configuration: InstallConfiguration(source: .automatic)
        )

        let progresses = ProgressRecorder()
        let observer = Task {
            for await progress in await environment.progressStream() {
                await progresses.append(progress)
            }
        }

        let python = try await environment.ensureInstalled()
        observer.cancel()

        #expect(FileManager.default.isExecutableFile(atPath: python.path))
        #expect(await environment.isInstalled())

        let recorded = await progresses.values
        let installPhases = recorded.filter { $0.phase == .installingDependencies }
        #expect(!installPhases.isEmpty)
        #expect(recorded.contains { $0.phase == .ready })
        // 依赖下载阶段必须有确定的进度值，否则 UI 只能转圈。
        #expect(installPhases.contains { $0.fraction != nil })

        for progress in recorded.suffix(6) {
            print("[progress] \(progress.phase.rawValue) \(progress.message) | \(progress.detail ?? "-") | \(progress.fraction ?? -1)")
        }
    }
}

private actor ProgressRecorder {
    private(set) var values: [InstallProgress] = []

    func append(_ progress: InstallProgress) {
        values.append(progress)
    }
}
