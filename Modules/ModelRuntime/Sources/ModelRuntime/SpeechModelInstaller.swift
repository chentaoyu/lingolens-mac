import Foundation

/// 语音识别引擎。
public enum SpeechEngine: String, Codable, CaseIterable, Sendable {
    /// 系统自带的 SpeechAnalyzer：零下载、实时草稿，但中英混说时英文缩写容易被音译。
    case apple
    /// 本地大模型（mlx-audio，默认 Qwen3-ASR）：中英混说准确得多，需要下载模型，字幕按句出现。
    /// case 名保留 whisper，兼容已保存的设置。
    case whisper

    public var displayName: String {
        switch self {
        case .apple: return "系统语音识别"
        case .whisper: return "本地模型（更准）"
        }
    }
}

/// 一次下载任务里的单个文件。
public struct SpeechModelFile: Sendable, Equatable {
    public let repository: String
    public let name: String
    public let expectedSize: Int64

    public init(repository: String, name: String, expectedSize: Int64) {
        self.repository = repository
        self.name = name
        self.expectedSize = expectedSize
    }
}

/// 一个可安装的本地语音模型（权重托管在魔搭）。
public struct SpeechModel: Sendable, Equatable {
    public let id: String
    public let displayName: String
    public let files: [SpeechModelFile]

    public init(id: String, displayName: String, files: [SpeechModelFile]) {
        self.id = id
        self.displayName = displayName
        self.files = files
    }

    public var totalBytes: Int64 { files.reduce(0) { $0 + $1.expectedSize } }

    /// 人类可读的体积，设置页展示用。
    public var sizeText: String {
        let mb = Double(totalBytes) / 1_000_000
        if mb >= 1000 { return String(format: "%.1f GB", mb / 1000) }
        return String(format: "%.0f MB", mb)
    }

    /// 最大的文件视为权重本体，用于安装完成校验。
    public var weightFile: SpeechModelFile? { files.max { $0.expectedSize < $1.expectedSize } }

    /// 解析实际要用的模型：显式选择优先（须已安装），否则按目录顺序取第一个已安装的。
    public static func resolve(preferredID: String?, installedIDs: Set<String>) -> SpeechModel? {
        if let preferredID,
           let preferred = all.first(where: { $0.id == preferredID }),
           installedIDs.contains(preferred.id) {
            return preferred
        }
        return all.first { installedIDs.contains($0.id) }
    }
}

extension SpeechModel {
    /// 默认模型：Qwen3-ASR-0.6B 8bit（约 1 GB）。WenetSpeech 会议测试集 CER 约 6.9%，
    /// 比 Whisper-large-v3 的 19.1% 好约 3 倍；支持热词与自动语种检测。
    public static let qwen3ASR = SpeechModel(
        id: "qwen3-asr-0.6b-8bit",
        displayName: "Qwen3-ASR 0.6B（8bit）",
        files: [
            SpeechModelFile(repository: "mlx-community/Qwen3-ASR-0.6B-8bit", name: "config.json", expectedSize: 7_187),
            SpeechModelFile(repository: "mlx-community/Qwen3-ASR-0.6B-8bit", name: "configuration.json", expectedSize: 64),
            SpeechModelFile(repository: "mlx-community/Qwen3-ASR-0.6B-8bit", name: "generation_config.json", expectedSize: 142),
            SpeechModelFile(repository: "mlx-community/Qwen3-ASR-0.6B-8bit", name: "preprocessor_config.json", expectedSize: 330),
            SpeechModelFile(repository: "mlx-community/Qwen3-ASR-0.6B-8bit", name: "chat_template.json", expectedSize: 1_161),
            SpeechModelFile(repository: "mlx-community/Qwen3-ASR-0.6B-8bit", name: "tokenizer_config.json", expectedSize: 12_487),
            SpeechModelFile(repository: "mlx-community/Qwen3-ASR-0.6B-8bit", name: "vocab.json", expectedSize: 2_776_833),
            SpeechModelFile(repository: "mlx-community/Qwen3-ASR-0.6B-8bit", name: "merges.txt", expectedSize: 1_671_853),
            SpeechModelFile(repository: "mlx-community/Qwen3-ASR-0.6B-8bit", name: "model.safetensors.index.json", expectedSize: 71_815),
            SpeechModelFile(repository: "mlx-community/Qwen3-ASR-0.6B-8bit", name: "model.safetensors", expectedSize: 1_006_229_426)
        ]
    )

    /// 旧默认模型（约 464 MB），保留作回退：已下载的用户不用重新下载。
    /// 官方模型仓库与量化权重仓库分开：魔搭上的 q4 仓库只放了 config 和权重。
    public static let whisperTurboQ4 = SpeechModel(
        id: "whisper-large-v3-turbo-q4",
        displayName: "Whisper large-v3-turbo（4bit）",
        files: [
            SpeechModelFile(repository: "mlx-community/whisper-large-v3-turbo-q4", name: "config.json", expectedSize: 341),
            SpeechModelFile(repository: "mlx-community/whisper-large-v3-turbo-q4", name: "weights.npz", expectedSize: 463_664_664),
            SpeechModelFile(repository: "AI-ModelScope/whisper-large-v3-turbo", name: "preprocessor_config.json", expectedSize: 340),
            SpeechModelFile(repository: "AI-ModelScope/whisper-large-v3-turbo", name: "generation_config.json", expectedSize: 3_772),
            SpeechModelFile(repository: "AI-ModelScope/whisper-large-v3-turbo", name: "tokenizer.json", expectedSize: 2_710_337),
            SpeechModelFile(repository: "AI-ModelScope/whisper-large-v3-turbo", name: "tokenizer_config.json", expectedSize: 282_843),
            SpeechModelFile(repository: "AI-ModelScope/whisper-large-v3-turbo", name: "vocab.json", expectedSize: 1_036_558),
            SpeechModelFile(repository: "AI-ModelScope/whisper-large-v3-turbo", name: "merges.txt", expectedSize: 493_869),
            SpeechModelFile(repository: "AI-ModelScope/whisper-large-v3-turbo", name: "special_tokens_map.json", expectedSize: 2_186),
            SpeechModelFile(repository: "AI-ModelScope/whisper-large-v3-turbo", name: "added_tokens.json", expectedSize: 34_648),
            SpeechModelFile(repository: "AI-ModelScope/whisper-large-v3-turbo", name: "normalizer.json", expectedSize: 52_666)
        ]
    )

    /// 安装候选按优先级排列：新模型在前，旧模型兜底。
    public static let all: [SpeechModel] = [.qwen3ASR, .whisperTurboQ4]
}

/// 从魔搭（ModelScope）下载语音模型。
///
/// 为什么不用 HuggingFace：实测这台机器直连 huggingface.co 完全超时，
/// 魔搭同样内容能跑到 2.6 MB/s，而且国内普遍可达。
public actor SpeechModelInstaller {
    public static let defaultModelID = SpeechModel.qwen3ASR.id

    public nonisolated let model: SpeechModel

    public struct Progress: Sendable, Equatable {
        public let completedBytes: Int64
        public let totalBytes: Int64
        public let currentFile: String

        public var fraction: Double {
            guard totalBytes > 0 else { return 0 }
            return min(1, Double(completedBytes) / Double(totalBytes))
        }
    }

    private let paths: RuntimePaths
    private let session: URLSession
    private let baseURL = "https://www.modelscope.cn/models"

    public init(paths: RuntimePaths, model: SpeechModel = .qwen3ASR) {
        self.paths = paths
        self.model = model
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 1800
        self.session = URLSession(configuration: configuration)
    }

    public nonisolated var directory: URL {
        paths.appSupportDirectory
            .appendingPathComponent("models-stt", isDirectory: true)
            .appendingPathComponent(model.id, isDirectory: true)
    }

    private nonisolated var markerURL: URL {
        directory.appendingPathComponent("installed.json")
    }

    /// 是否已经装好：标记文件存在且权重文件大小对得上。
    public nonisolated var isInstalled: Bool {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: markerURL.path) else { return false }
        guard let weight = model.weightFile else { return false }
        let url = directory.appendingPathComponent(weight.name)
        guard let size = (try? fileManager.attributesOfItem(atPath: url.path)[.size]) as? Int64 else {
            return false
        }
        // 允许 1% 误差：不同 CDN 的 npz 打包体积可能略有差异。
        return abs(size - weight.expectedSize) <= max(weight.expectedSize / 100, 1024)
    }

    /// 下载缺失或大小不符的文件。已存在的文件跳过，支持断点续传。
    public func install(progress: @Sendable (Progress) -> Void) async throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        var completed: Int64 = 0
        let total = model.totalBytes

        for file in model.files {
            let destination = directory.appendingPathComponent(file.name)
            let existing = (try? fileManager.attributesOfItem(atPath: destination.path)[.size]) as? Int64 ?? 0
            if existing == file.expectedSize {
                completed += existing
                progress(Progress(completedBytes: completed, totalBytes: total, currentFile: file.name))
                continue
            }

            // 闭包在别处执行，用不可变快照，避免捕获可变变量。
            let baseline = completed
            let fileName = file.name
            try await download(file, to: destination, alreadyHave: existing) { written in
                progress(Progress(
                    completedBytes: baseline + written,
                    totalBytes: total,
                    currentFile: fileName
                ))
            }
            completed += file.expectedSize
            progress(Progress(completedBytes: completed, totalBytes: total, currentFile: file.name))
        }

        let marker: [String: Any] = [
            "modelID": model.id,
            "installedAt": ISO8601DateFormatter().string(from: Date()),
            "bytes": total
        ]
        let data = try JSONSerialization.data(withJSONObject: marker, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: markerURL, options: .atomic)
    }

    public func remove() throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    // MARK: - 私有

    private func download(
        _ file: SpeechModelFile,
        to destination: URL,
        alreadyHave: Int64,
        onProgress: @Sendable (Int64) -> Void
    ) async throws {
        guard let url = URL(string: "\(baseURL)/\(file.repository)/resolve/master/\(file.name)") else {
            throw SpeechModelError.invalidURL(file.name)
        }
        var request = URLRequest(url: url)
        if alreadyHave > 0 {
            request.setValue("bytes=\(alreadyHave)-", forHTTPHeaderField: "Range")
        }

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SpeechModelError.badResponse(file.name, -1)
        }
        // 服务器不支持续传就走全量重下。
        let resuming = http.statusCode == 206 && alreadyHave > 0
        guard http.statusCode == 200 || http.statusCode == 206 else {
            throw SpeechModelError.badResponse(file.name, http.statusCode)
        }

        let partial = destination.appendingPathExtension("part")
        if !resuming, FileManager.default.fileExists(atPath: partial.path) {
            try FileManager.default.removeItem(at: partial)
        }
        if !FileManager.default.fileExists(atPath: partial.path) {
            FileManager.default.createFile(atPath: partial.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: partial)
        defer { try? handle.close() }
        if resuming {
            try handle.seekToEnd()
        }

        var written = resuming ? alreadyHave : 0
        var buffer = Data()
        buffer.reserveCapacity(1 << 20)
        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= (1 << 20) {
                try handle.write(contentsOf: buffer)
                written += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                onProgress(written)
            }
        }
        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
            written += Int64(buffer.count)
        }
        try handle.close()

        // 大小对不上就当失败，宁可重来也别把坏文件当模型。
        let finalSize = (try? FileManager.default.attributesOfItem(atPath: partial.path)[.size]) as? Int64 ?? 0
        guard abs(finalSize - file.expectedSize) <= max(file.expectedSize / 100, 1024) else {
            try? FileManager.default.removeItem(at: partial)
            throw SpeechModelError.sizeMismatch(file.name, finalSize, file.expectedSize)
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: partial, to: destination)
    }
}

public enum SpeechModelError: Error, LocalizedError, Equatable {
    case invalidURL(String)
    case badResponse(String, Int)
    case sizeMismatch(String, Int64, Int64)

    public var errorDescription: String? {
        switch self {
        case let .invalidURL(name): return "模型地址无效：" + name
        case let .badResponse(name, status): return "下载 " + name + " 失败（HTTP " + String(status) + "）"
        case let .sizeMismatch(name, actual, expected):
            return name + " 体积不符（实际 " + String(actual) + "，预期 " + String(expected) + "），已删除，请重试"
        }
    }
}
