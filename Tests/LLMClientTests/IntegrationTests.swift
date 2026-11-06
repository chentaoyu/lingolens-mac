import Foundation
import ModelRuntime
import Testing
@testable import LLMClient

/// 需要真实模型与已安装的运行时，默认跳过。
///
/// 运行方式：
/// ```
/// LINGOLENS_INTEGRATION_MODEL=~/models/Qwen3.5-4B-MLX-4bit swift test --filter Integration
/// ```
@Suite("集成测试（需真实模型）")
struct RealServerIntegrationTests {
    @Test(
        "启动真实 mlx_vlm.server 并完成一次翻译",
        .enabled(if: ProcessInfo.processInfo.environment["LINGOLENS_INTEGRATION_MODEL"] != nil)
    )
    func realTranslation() async throws {
        let modelPath = try #require(ProcessInfo.processInfo.environment["LINGOLENS_INTEGRATION_MODEL"])
        let paths = RuntimePaths.standard()
        try paths.prepare()

        let python = PythonEnvironment(paths: paths)
        _ = try await python.ensureInstalled()

        let pool = ServerPool(
            paths: paths,
            python: python,
            readinessTimeout: 180,
            cleanupStaleProcesses: false
        )
        let model = ModelRef(
            id: "integration",
            name: "integration-model",
            directory: URL(fileURLWithPath: modelPath, isDirectory: true)
        )

        do {
            let lease = try await pool.acquire(
                model: model,
                config: ServerLaunchConfig(isResident: true)
            )
            // 服务端 /v1/models 返回的 id 才是 Chat Completions 的 model 字段。
            #expect(lease.serverModelID.contains("Qwen3.5-4B"))

            let client = LocalLLMClient()
            let request = ChatRequest(
                model: lease.serverModelID,
                messages: [.user("把 hello 翻译成中文，只输出译文。")],
                parameters: .selectionTranslation
            )

            var output = ""
            var metrics: ChatMetrics?
            for try await event in client.streamChat(baseURL: lease.baseURL, request: request) {
                switch event {
                case let .delta(text):
                    output += text
                case let .finished(value):
                    metrics = value
                }
            }

            await pool.release(lease)
            await pool.shutdown()

            #expect(!output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(metrics?.timeToFirstToken != nil)
        } catch {
            await pool.shutdown()
            throw error
        }
    }
}
