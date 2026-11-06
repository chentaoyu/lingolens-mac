import Foundation
import LLMClient
import ModelLibrary
import ModelRuntime
import Settings
import Testing
@testable import SelectionTranslate

/// 真实模型下的划词翻译链路（设置 → 模型解析 → 服务 → 流式译文），默认跳过。
@Suite("集成：划词翻译链路")
struct TranslationServiceIntegrationTests {
    @Test(
        "使用常驻模型完成一次真实翻译",
        .enabled(if: ProcessInfo.processInfo.environment["LINGOLENS_INTEGRATION_MODEL"] != nil)
    )
    @MainActor
    func realTranslationThroughService() async throws {
        let modelPath = try #require(ProcessInfo.processInfo.environment["LINGOLENS_INTEGRATION_MODEL"])
        let modelDirectory = URL(fileURLWithPath: modelPath, isDirectory: true)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LingoSvcTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let settingsURL = root.appendingPathComponent("settings.json")
        var settings = AppSettings(residentModelID: modelDirectory.standardizedFileURL.path)
        settings.setScene(
            SceneSettings(useResidentModel: true, modelID: nil, parameters: .selectionTranslation),
            for: .selectionTranslation
        )
        try SettingsPersistence.save(settings, to: settingsURL)
        let store = SettingsStore(fileURL: settingsURL)
        let catalog = ModelCatalog(fileURL: root.appendingPathComponent("library.json"))
        _ = try await catalog.importModel(at: modelDirectory)

        let paths = RuntimePaths.standard()
        let python = PythonEnvironment(paths: paths)
        _ = try await python.ensureInstalled()
        let pool = ServerPool(
            paths: paths,
            python: python,
            readinessTimeout: 180,
            cleanupStaleProcesses: false
        )
        let service = TranslationService(
            client: LocalLLMClient(),
            pool: pool,
            settingsStore: store,
            catalog: catalog
        )

        do {
            var output = ""
            var sawModel = false
            for try await event in service.translate(text: "Hello, how are you?") {
                switch event {
                case let .modelResolved(name):
                    sawModel = !name.isEmpty
                case let .delta(text):
                    output += text
                case .finished:
                    break
                }
            }
            await pool.shutdown()

            #expect(sawModel)
            #expect(!output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } catch {
            await pool.shutdown()
            throw error
        }
    }
}
