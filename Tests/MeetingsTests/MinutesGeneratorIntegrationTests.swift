import AudioCapture
import Foundation
import LLMClient
import Meetings
import ModelLibrary
import ModelRuntime
import SceneChat
import Settings
import Testing

/// 真实模型下的纪要生成（需要 LINGOLENS_INTEGRATION_MODEL），默认跳过。
@Suite("集成：会议纪要")
struct MinutesGeneratorIntegrationTests {
    @Test(
        "用真实模型生成 Markdown 纪要",
        .enabled(if: ProcessInfo.processInfo.environment["LINGOLENS_INTEGRATION_MODEL"] != nil)
    )
    @MainActor
    func generateMinutes() async throws {
        let modelPath = try #require(ProcessInfo.processInfo.environment["LINGOLENS_INTEGRATION_MODEL"])
        let modelDirectory = URL(fileURLWithPath: modelPath, isDirectory: true)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LingoMinutes-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let settingsURL = root.appendingPathComponent("settings.json")
        var settings = AppSettings(residentModelID: modelDirectory.standardizedFileURL.path)
        settings.setScene(
            SceneSettings(useResidentModel: true, modelID: nil, parameters: .meetingMinutes),
            for: .meetingMinutes
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
        let chat = SceneChatService(
            client: LocalLLMClient(),
            pool: pool,
            settingsStore: store,
            catalog: catalog
        )
        let generator = MinutesGenerator(chat: chat, settingsStore: store)

        let meeting = MeetingDetail(
            meta: MeetingMeta(
                id: "integration",
                title: "集成测试会议",
                startedAt: Date(),
                endedAt: Date(),
                languages: ["other": "en", "me": "zh-Hans"]
            ),
            entries: [
                TranscriptEntry(
                    time: Date(),
                    speaker: .other,
                    text: "We decided to ship the beta next Friday."
                ),
                TranscriptEntry(
                    time: Date(),
                    speaker: .me,
                    text: "我会负责准备发布说明。"
                )
            ],
            minutes: nil
        )

        do {
            var output = ""
            var sawPhase = false
            for try await event in generator.generate(
                meeting: meeting,
                template: .standard,
                targetLanguage: "简体中文"
            ) {
                switch event {
                case .phase:
                    sawPhase = true
                case let .delta(text):
                    output += text
                case .finished:
                    break
                }
            }
            await pool.shutdown()

            #expect(sawPhase)
            #expect(!output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(output.contains("摘要") || output.contains("#"))
        } catch {
            await pool.shutdown()
            throw error
        }
    }
}
