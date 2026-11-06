import Foundation
import Testing
@testable import ModelLibrary

private func makeTempDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("LingoModelTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func writeSafetensors(at url: URL, tensors: [String: [Int]]) throws {
    var header: [String: Any] = [:]
    for (name, shape) in tensors {
        header[name] = ["dtype": "F16", "shape": shape, "data_offsets": [0, 0]]
    }
    let headerData = try JSONSerialization.data(withJSONObject: header, options: [.sortedKeys])
    var length = UInt64(headerData.count).littleEndian
    var data = Data(bytes: &length, count: 8)
    data.append(headerData)
    try data.write(to: url)
}

private func writeModel(
    at directory: URL,
    config: [String: Any],
    tensors: [String: [Int]] = ["weight": [2, 3]]
) throws -> URL {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let configData = try JSONSerialization.data(withJSONObject: config, options: [.sortedKeys])
    try configData.write(to: directory.appendingPathComponent("config.json"))
    try writeSafetensors(at: directory.appendingPathComponent("model.safetensors"), tensors: tensors)
    return directory
}

private func makeModelDirectory(
    named name: String,
    config: [String: Any],
    tensors: [String: [Int]] = ["weight": [2, 3]]
) throws -> URL {
    let directory = try makeTempDirectory().appendingPathComponent(name, isDirectory: true)
    return try writeModel(at: directory, config: config, tensors: tensors)
}

@Suite("模型识别")
struct ModelInspectorTests {
    @Test("MLX 量化模型目录识别与信息解析")
    func inspectQuantizedModel() throws {
        let directory = try makeModelDirectory(
            named: "Qwen3.5-4B-MLX-4bit",
            config: [
                "quantization": ["bits": 4, "group_size": 64],
                "max_position_embeddings": 32768,
                "vision_config": ["depth": 1],
                "architectures": ["Qwen2VLForConditionalGeneration"]
            ],
            tensors: ["weight": [4, 5], "bias": [5]]
        )
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }

        #expect(ModelInspector.isModelDirectory(directory))
        #expect(ModelInspector.looksLikeMLXModel(directory: directory))

        let info = try #require(ModelInspector.inspect(directory: directory))
        #expect(info.quantizationBits == 4)
        #expect(info.parameterCount == 25)
        #expect(info.contextLength == 32768)
        #expect(info.supportsVision)
        #expect(info.diskSizeBytes > 0)
        #expect(info.estimatedMemoryBytes > 0)
    }

    @Test("目录名含 mlx 时即使没有量化信息也识别")
    func mlxNameFallback() throws {
        let directory = try makeModelDirectory(named: "Llama-3.2-3B-Instruct-MLX-8bit", config: ["model_type": "llama"])
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }

        #expect(ModelInspector.looksLikeMLXModel(directory: directory))
        let info = try #require(ModelInspector.inspect(directory: directory))
        #expect(info.quantizationBits == 8)
    }

    @Test("普通目录不会被识别为模型")
    func nonModelDirectory() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("{}".utf8).write(to: directory.appendingPathComponent("config.json"))
        #expect(!ModelInspector.isModelDirectory(directory))
    }
}

@Suite("模型扫描")
struct ModelScannerTests {
    @Test("递归扫描并过滤非 MLX 目录")
    func scanNested() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let mlx = try writeModel(
            at: root.appendingPathComponent("nested/Qwen-MLX-4bit", isDirectory: true),
            config: ["quantization": ["bits": 4]]
        )
        let plain = try writeModel(
            at: root.appendingPathComponent("nested/plain-model", isDirectory: true),
            config: ["model_type": "llama"]
        )

        let found = ModelScanner().scan(roots: [root])
        let paths = found.map(\.standardizedFileURL.path)
        #expect(paths.contains(mlx.standardizedFileURL.path))
        #expect(!paths.contains(plain.standardizedFileURL.path))
    }

    @Test("不存在的根目录返回空")
    func missingRoot() {
        let found = ModelScanner().scan(roots: [URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")])
        #expect(found.isEmpty)
    }
}

@Suite("模型列表")
struct ModelCatalogTests {
    @Test("扫描结果合并、移除扫描项不删除文件")
    func syncScanned() async throws {
        let directory = try makeModelDirectory(named: "Qwen-MLX-4bit", config: ["quantization": ["bits": 4]])
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
        let libraryURL = directory.deletingLastPathComponent().appendingPathComponent("library.json")

        let catalog = ModelCatalog(fileURL: libraryURL)
        let records = await catalog.syncScanned(candidates: [directory])
        #expect(records.count == 1)
        #expect(records.first?.source == .scanned)
        #expect(records.first?.isAvailable == true)

        let empty = await catalog.syncScanned(candidates: [])
        #expect(empty.isEmpty)
        #expect(FileManager.default.fileExists(atPath: directory.path))
    }

    @Test("导入校验与移除行为")
    func importAndRemove() async throws {
        let modelDir = try makeModelDirectory(named: "Imported-MLX-4bit", config: ["quantization": ["bits": 4]])
        defer { try? FileManager.default.removeItem(at: modelDir.deletingLastPathComponent()) }
        let libraryURL = modelDir.deletingLastPathComponent().appendingPathComponent("library.json")
        let invalid = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: invalid) }

        let catalog = ModelCatalog(fileURL: libraryURL)
        await #expect(throws: ModelLibraryError.self) {
            _ = try await catalog.importModel(at: invalid)
        }

        let record = try await catalog.importModel(at: modelDir)
        #expect(record.source == .imported)
        #expect(record.isAvailable)

        try await catalog.remove(id: record.id)
        let remaining = await catalog.all()
        #expect(remaining.isEmpty)
        #expect(FileManager.default.fileExists(atPath: modelDir.path))
    }

    @Test("删除下载的模型会删除文件")
    func removeDownloadedDeletesFiles() async throws {
        let modelDir = try makeModelDirectory(named: "Downloaded-MLX-4bit", config: ["quantization": ["bits": 4]])
        defer { try? FileManager.default.removeItem(at: modelDir.deletingLastPathComponent()) }
        let libraryURL = modelDir.deletingLastPathComponent().appendingPathComponent("library.json")

        let catalog = ModelCatalog(fileURL: libraryURL)
        let record = await catalog.registerDownloaded(at: modelDir, name: "Downloaded")
        #expect(record.source == .downloaded)

        try await catalog.remove(id: record.id)
        #expect(!FileManager.default.fileExists(atPath: modelDir.path))
    }

    @Test("路径失效后刷新为不可用")
    func refreshAvailability() async throws {
        let modelDir = try makeModelDirectory(named: "Temp-MLX-4bit", config: ["quantization": ["bits": 4]])
        let libraryURL = modelDir.deletingLastPathComponent().appendingPathComponent("library.json")
        defer { try? FileManager.default.removeItem(at: modelDir.deletingLastPathComponent()) }

        let catalog = ModelCatalog(fileURL: libraryURL)
        _ = try await catalog.importModel(at: modelDir)
        try FileManager.default.removeItem(at: modelDir)

        let refreshed = await catalog.refreshAvailability()
        #expect(refreshed.first?.isAvailable == false)
    }
}

@Suite("Hugging Face 下载参数")
struct HFDownloaderTests {
    @Test("仓库 ID 校验")
    func repoValidation() {
        #expect(HFDownloader.isValidRepositoryID("mlx-community/Qwen3.5-4B-MLX-4bit"))
        #expect(!HFDownloader.isValidRepositoryID(""))
        #expect(!HFDownloader.isValidRepositoryID("../etc/passwd"))
        #expect(!HFDownloader.isValidRepositoryID("/absolute"))
    }

    @Test("路径逐段编码")
    func pathEncoding() {
        #expect(HFDownloader.encodedPath("a/b c") == "a/b%20c")
    }
}
