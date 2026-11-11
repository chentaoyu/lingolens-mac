import Foundation
import Testing
@testable import ModelRuntime

@Suite("语音模型安装器")
struct SpeechModelInstallerTests {
    private func makePaths() -> RuntimePaths {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LingoSpeech-\(UUID().uuidString)", isDirectory: true)
        let paths = RuntimePaths(
            appSupportDirectory: root.appendingPathComponent("support", isDirectory: true),
            logsDirectory: root.appendingPathComponent("logs", isDirectory: true)
        )
        try? paths.prepare()
        return paths
    }

    @Test("默认模型文件清单包含权重与分词器")
    func fileList() {
        let names = SpeechModel.qwen3ASR.files.map(\.name)
        #expect(names.contains("model.safetensors"))
        #expect(names.contains("config.json"))
        #expect(names.contains("tokenizer_config.json"))
        #expect(names.contains("preprocessor_config.json"))
        #expect(SpeechModel.qwen3ASR.totalBytes > 900_000_000)
    }

    @Test("旧 Whisper 模型保留作回退")
    func legacyWhisperCatalog() {
        let names = SpeechModel.whisperTurboQ4.files.map(\.name)
        #expect(names.contains("weights.npz"))
        #expect(names.contains("tokenizer.json"))
        #expect(SpeechModel.whisperTurboQ4.totalBytes > 400_000_000)
        #expect(SpeechModel.all.first == .qwen3ASR)
    }

    @Test("未下载时 isInstalled 为 false")
    func notInstalledByDefault() {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.appSupportDirectory.deletingLastPathComponent()) }
        #expect(!SpeechModelInstaller(paths: paths).isInstalled)
    }

    @Test("只有标记、没有权重不算装好")
    func requiresMarkerAndWeights() throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.appSupportDirectory.deletingLastPathComponent()) }
        let installer = SpeechModelInstaller(paths: paths)
        try FileManager.default.createDirectory(at: installer.directory, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: installer.directory.appendingPathComponent("installed.json"))
        #expect(!installer.isInstalled)
    }

    @Test("模型目录位于 App 数据目录下")
    func directoryLocation() {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.appSupportDirectory.deletingLastPathComponent()) }
        let installer = SpeechModelInstaller(paths: paths)
        #expect(installer.directory.path.hasPrefix(paths.appSupportDirectory.path))
        #expect(installer.directory.lastPathComponent == SpeechModelInstaller.defaultModelID)
    }
}
