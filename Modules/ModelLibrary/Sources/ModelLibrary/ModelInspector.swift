import Foundation

public enum ModelInspector {
    /// 目录是否包含 config.json 与直系 *.safetensors。
    public static func isModelDirectory(_ directory: URL) -> Bool {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return false
        }
        guard fileManager.fileExists(atPath: directory.appendingPathComponent("config.json").path) else {
            return false
        }
        return !safetensorsFiles(in: directory).isEmpty
    }

    /// 扫描判定：模型目录 + MLX 特征（量化信息或名称含 mlx）。
    public static func looksLikeMLXModel(directory: URL) -> Bool {
        guard isModelDirectory(directory), let config = readConfig(directory) else { return false }
        if config["quantization"] != nil { return true }
        if let quantization = config["quantization_config"] as? [String: Any], quantization["bits"] != nil {
            return true
        }
        let hints = [directory.lastPathComponent, directory.deletingLastPathComponent().lastPathComponent]
        return hints.contains { $0.lowercased().contains("mlx") }
    }

    public static func readConfig(_ directory: URL) -> [String: Any]? {
        let url = directory.appendingPathComponent("config.json")
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object
    }

    public static func inspect(directory: URL) -> ModelInfo? {
        guard let config = readConfig(directory) else { return nil }
        let files = safetensorsFiles(in: directory)
        guard !files.isEmpty else { return nil }

        var parameters: Int64 = 0
        for file in files {
            parameters += tensorParameterCount(in: file) ?? 0
        }

        let weightsBytes = files.reduce(Int64(0)) { partial, url in
            partial + Int64(fileSize(url))
        }
        let estimatedMemory = weightsBytes > 0 ? weightsBytes * 115 / 100 + 512 * 1024 * 1024 : 0

        return ModelInfo(
            parameterCount: parameters > 0 ? parameters : nil,
            quantizationBits: quantizationBits(config: config, directoryName: directory.lastPathComponent),
            diskSizeBytes: directorySize(directory),
            estimatedMemoryBytes: estimatedMemory,
            supportsVision: supportsVision(config: config),
            architecture: architecture(config: config),
            contextLength: contextLength(config: config)
        )
    }

    public static func quantizationBits(config: [String: Any], directoryName: String) -> Int? {
        if let quantization = config["quantization"] as? [String: Any], let bits = quantization["bits"] as? Int {
            return bits
        }
        if let quantization = config["quantization_config"] as? [String: Any], let bits = quantization["bits"] as? Int {
            return bits
        }
        if let textConfig = config["text_config"] as? [String: Any],
           let quantization = textConfig["quantization"] as? [String: Any],
           let bits = quantization["bits"] as? Int {
            return bits
        }
        let pattern = #"(?i)(\d{1,2})\s*-?\s*bit"#
        if let match = directoryName.range(of: pattern, options: .regularExpression) {
            let digits = directoryName[match].filter(\.isNumber)
            return Int(digits)
        }
        return nil
    }

    public static func contextLength(config: [String: Any]) -> Int? {
        if let value = config["max_position_embeddings"] as? Int { return value }
        if let textConfig = config["text_config"] as? [String: Any],
           let value = textConfig["max_position_embeddings"] as? Int {
            return value
        }
        return nil
    }

    public static func supportsVision(config: [String: Any]) -> Bool {
        if config["vision_config"] != nil { return true }
        if let modelType = config["model_type"] as? String, modelType.lowercased().contains("vision") { return true }
        if let architectures = config["architectures"] as? [String],
           architectures.contains(where: { $0.lowercased().contains("vision") }) {
            return true
        }
        return false
    }

    private static func architecture(config: [String: Any]) -> String? {
        if let architectures = config["architectures"] as? [String], let first = architectures.first {
            return first
        }
        return config["model_type"] as? String
    }

    public static func safetensorsFiles(in directory: URL) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return contents.filter { url in
            guard url.pathExtension.lowercased() == "safetensors" else { return false }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            return values?.isRegularFile ?? false
        }
    }

    /// 读取 safetensors 头部 JSON，累加所有张量的元素数。
    public static func tensorParameterCount(in url: URL) -> Int64? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        guard let lengthData = try? handle.read(upToCount: 8), lengthData.count == 8 else { return nil }
        let headerLength = lengthData.withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }.littleEndian
        guard headerLength > 0, headerLength < 200_000_000 else { return nil }
        guard let headerData = try? handle.read(upToCount: Int(headerLength)), headerData.count == Int(headerLength) else {
            return nil
        }
        guard let object = try? JSONSerialization.jsonObject(with: headerData) as? [String: Any] else {
            return nil
        }

        var total: Int64 = 0
        for (key, value) in object where key != "__metadata__" {
            guard let tensor = value as? [String: Any], let shape = tensor["shape"] as? [Int] else { continue }
            total += shape.reduce(Int64(1)) { $0 * Int64($1) }
        }
        return total
    }

    public static func fileSize(_ url: URL) -> UInt64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return UInt64(max(0, values?.fileSize ?? 0))
    }

    public static func directorySize(_ directory: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true,
                  let size = values.fileSize
            else { continue }
            total += Int64(size)
        }
        return total
    }

    /// 从 HF 缓存或 Models 目录推导可读名称。
    public static func displayName(for directory: URL) -> String {
        let components = directory.standardizedFileURL.pathComponents
        if let index = components.lastIndex(where: { $0.hasPrefix("models--") }) {
            return components[index]
                .replacingOccurrences(of: "models--", with: "")
                .replacingOccurrences(of: "--", with: "/")
        }
        let name = directory.lastPathComponent
        if name.count >= 12, name.allSatisfy({ $0.isHexDigit }) {
            // HF snapshot 目录名是 commit hash，回退到模型名层。
            return directory.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
                .replacingOccurrences(of: "models--", with: "")
                .replacingOccurrences(of: "--", with: "/")
        }
        return name
    }
}
