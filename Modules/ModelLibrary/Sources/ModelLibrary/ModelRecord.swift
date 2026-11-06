import Foundation

public enum ModelSource: String, Codable, Sendable {
    case scanned
    case imported
    case downloaded
}

public struct ModelInfo: Codable, Sendable, Equatable {
    public var parameterCount: Int64?
    public var quantizationBits: Int?
    public var diskSizeBytes: Int64
    public var estimatedMemoryBytes: Int64
    public var supportsVision: Bool
    public var architecture: String?
    public var contextLength: Int?

    public init(
        parameterCount: Int64? = nil,
        quantizationBits: Int? = nil,
        diskSizeBytes: Int64 = 0,
        estimatedMemoryBytes: Int64 = 0,
        supportsVision: Bool = false,
        architecture: String? = nil,
        contextLength: Int? = nil
    ) {
        self.parameterCount = parameterCount
        self.quantizationBits = quantizationBits
        self.diskSizeBytes = diskSizeBytes
        self.estimatedMemoryBytes = estimatedMemoryBytes
        self.supportsVision = supportsVision
        self.architecture = architecture
        self.contextLength = contextLength
    }
}

public struct ModelRecord: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var name: String
    public var path: String
    public var source: ModelSource
    public var addedAt: Date
    public var info: ModelInfo?
    public var isAvailable: Bool

    public init(
        id: String,
        name: String,
        path: String,
        source: ModelSource,
        addedAt: Date,
        info: ModelInfo?,
        isAvailable: Bool
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.source = source
        self.addedAt = addedAt
        self.info = info
        self.isAvailable = isAvailable
    }

    public var directoryURL: URL { URL(fileURLWithPath: path, isDirectory: true) }

    public var sourceLabel: String {
        switch source {
        case .scanned: return "扫描"
        case .imported: return "导入"
        case .downloaded: return "下载"
        }
    }
}

public enum ModelLibraryError: Error, LocalizedError, Equatable, Sendable {
    case notAModelDirectory(String)
    case invalidRepository(String)
    case listingFailed(String)
    case downloadFailed(file: String, status: Int)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case let .notAModelDirectory(path):
            return "所选文件夹不是模型目录（需要包含 config.json 与 *.safetensors）：\(path)"
        case let .invalidRepository(repoID):
            return "无效的 Hugging Face 仓库 ID：\(repoID)"
        case let .listingFailed(message):
            return "获取仓库文件列表失败：\(message)"
        case let .downloadFailed(file, status):
            return "下载 \(file) 失败（HTTP \(status)）。"
        case .cancelled:
            return "下载已取消。"
        }
    }
}

public struct DownloadProgress: Sendable, Equatable {
    public var repoID: String
    public var fileIndex: Int
    public var fileCount: Int
    public var currentFile: String
    public var fileBytesDownloaded: Int64
    public var fileTotalBytes: Int64?

    public init(
        repoID: String,
        fileIndex: Int,
        fileCount: Int,
        currentFile: String,
        fileBytesDownloaded: Int64,
        fileTotalBytes: Int64?
    ) {
        self.repoID = repoID
        self.fileIndex = fileIndex
        self.fileCount = fileCount
        self.currentFile = currentFile
        self.fileBytesDownloaded = fileBytesDownloaded
        self.fileTotalBytes = fileTotalBytes
    }

    public var fileFraction: Double? {
        guard let total = fileTotalBytes, total > 0 else { return nil }
        return min(1, Double(fileBytesDownloaded) / Double(total))
    }
}
