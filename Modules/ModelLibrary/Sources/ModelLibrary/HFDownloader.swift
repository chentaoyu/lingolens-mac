import Foundation

/// 模型文件的下载来源（与 ModelRecord.source「模型从哪来」是两回事）。
///
/// 默认 `automatic`：先走魔搭（国内可达，实测 10 MB/s），失败再回退 Hugging Face。
/// 实测 Hugging Face 在国内经常直接超时，所以不能把它当首选。
public enum ModelDownloadSource: String, Codable, Sendable, CaseIterable {
    case automatic
    case modelScope
    case huggingFace

    public var displayName: String {
        switch self {
        case .automatic: return "自动（魔搭优先）"
        case .modelScope: return "魔搭 ModelScope"
        case .huggingFace: return "Hugging Face"
        }
    }
}

/// 从模型仓库下载文件到应用模型目录，支持断点续传、进度与取消。
public actor HFDownloader {
    private struct ModelAPIResponse: Decodable {
        struct Sibling: Decodable {
            let rfilename: String
        }
        let siblings: [Sibling]?
    }

    /// 魔搭的文件列表响应。
    private struct ModelScopeResponse: Decodable {
        struct DataBlock: Decodable {
            struct File: Decodable {
                let path: String
                enum CodingKeys: String, CodingKey { case path = "Path" }
            }
            let files: [File]
            enum CodingKeys: String, CodingKey { case files = "Files" }
        }
        let data: DataBlock
        enum CodingKeys: String, CodingKey { case data = "Data" }
    }

    private let modelsDirectory: URL
    private let session: URLSession

    /// 首启自动下载用的推荐模型（魔搭与 Hugging Face 同名同内容）。
    public static let recommendedRepositoryID = "mlx-community/Qwen3.5-4B-MLX-4bit"

    public init(modelsDirectory: URL, session: URLSession = .shared) {
        self.modelsDirectory = modelsDirectory
        self.session = session
    }

    /// 下载仓库全部文件，返回模型目录。
    ///
    /// 取消由调用方的结构化取消驱动（取消外层 Task 即可中断），已下载的
    /// `.part` 文件会保留，下次继续续传。
    @discardableResult
    public func download(
        repoID: String,
        source: ModelDownloadSource = .automatic,
        progress: @escaping @Sendable (DownloadProgress) -> Void = { _ in }
    ) async throws -> URL {
        let trimmed = repoID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidRepositoryID(trimmed) else {
            throw ModelLibraryError.invalidRepository(repoID)
        }

        // automatic：先用魔搭列出文件，拿不到再回退 Hugging Face。
        switch source {
        case .modelScope:
            return try await performDownload(repoID: trimmed, source: .modelScope, progress: progress)
        case .huggingFace:
            return try await performDownload(repoID: trimmed, source: .huggingFace, progress: progress)
        case .automatic:
            do {
                return try await performDownload(repoID: trimmed, source: .modelScope, progress: progress)
            } catch {
                return try await performDownload(repoID: trimmed, source: .huggingFace, progress: progress)
            }
        }
    }

    private func performDownload(
        repoID: String,
        source: ModelDownloadSource,
        progress: @escaping @Sendable (DownloadProgress) -> Void
    ) async throws -> URL {
        let files = try await listFiles(repoID: repoID, source: source)
        guard !files.isEmpty else {
            throw ModelLibraryError.listingFailed("仓库中没有可下载的文件")
        }

        let destinationRoot = destinationDirectory(for: repoID)
        try FileManager.default.createDirectory(at: destinationRoot, withIntermediateDirectories: true)

        for (index, file) in files.enumerated() {
            try Task.checkCancellation()
            let destination = destinationRoot.appendingPathComponent(file)
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if FileManager.default.fileExists(atPath: destination.path) {
                // 上一轮已完整下载。
                progress(DownloadProgress(
                    repoID: repoID, fileIndex: index, fileCount: files.count,
                    currentFile: file, fileBytesDownloaded: 0, fileTotalBytes: nil
                ))
                continue
            }
            try await downloadFile(
                repoID: repoID,
                source: source,
                file: file,
                destination: destination,
                fileIndex: index,
                fileCount: files.count,
                progress: progress
            )
        }
        return destinationRoot
    }

    private func listFiles(repoID: String, source: ModelDownloadSource) async throws -> [String] {
        let urlString = source == .modelScope
            ? "https://www.modelscope.cn/api/v1/models/" + Self.encodedPath(repoID) + "/repo/files"
            : "https://huggingface.co/api/models/" + Self.encodedPath(repoID)
        guard let url = URL(string: urlString) else {
            throw ModelLibraryError.invalidRepository(repoID)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw ModelLibraryError.listingFailed("HTTP \(code)")
        }

        let names: [String]
        if source == .modelScope {
            guard let payload = try? JSONDecoder().decode(ModelScopeResponse.self, from: data) else {
                throw ModelLibraryError.listingFailed("无法解析魔搭仓库信息")
            }
            names = payload.data.files.map(\.path)
        } else {
            guard let payload = try? JSONDecoder().decode(ModelAPIResponse.self, from: data) else {
                throw ModelLibraryError.listingFailed("无法解析仓库信息")
            }
            names = (payload.siblings ?? []).map(\.rfilename)
        }

        return names.filter {
            !$0.isEmpty
                && !$0.hasSuffix(".gitattributes")
                && !$0.contains("..")
                && !$0.hasSuffix("README.md")
        }
    }

    private func downloadFile(
        repoID: String,
        source: ModelDownloadSource,
        file: String,
        destination: URL,
        fileIndex: Int,
        fileCount: Int,
        progress: @escaping @Sendable (DownloadProgress) -> Void
    ) async throws {
        let fileManager = FileManager.default
        let partial = destination.appendingPathExtension("part")
        var offset = Int64(ModelInspector.fileSize(partial))

        // 魔搭用 /resolve/master/，Hugging Face 用 /resolve/main/。
        let urlString = source == .modelScope
            ? "https://www.modelscope.cn/models/" + Self.encodedPath(repoID)
                + "/resolve/master/" + Self.encodedPath(file)
            : "https://huggingface.co/" + Self.encodedPath(repoID)
                + "/resolve/main/" + Self.encodedPath(file) + "?download=true"
        guard let url = URL(string: urlString) else {
            throw ModelLibraryError.downloadFailed(file: file, status: 0)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        if offset > 0 {
            request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range")
        }

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ModelLibraryError.downloadFailed(file: file, status: -1)
        }
        if http.statusCode == 416, offset > 0 {
            try finalize(partial: partial, destination: destination)
            return
        }
        guard http.statusCode == 200 || http.statusCode == 206 else {
            throw ModelLibraryError.downloadFailed(file: file, status: http.statusCode)
        }
        if http.statusCode == 200, offset > 0 {
            try? fileManager.removeItem(at: partial)
            offset = 0
        }
        if !fileManager.fileExists(atPath: partial.path) {
            fileManager.createFile(atPath: partial.path, contents: nil)
        }

        let handle = try FileHandle(forWritingTo: partial)
        defer { try? handle.close() }
        if offset > 0 {
            try handle.seekToEnd()
        }

        let totalBytes = http.expectedContentLength > 0 ? offset + http.expectedContentLength : nil
        var downloaded = offset
        var buffer = Data()
        buffer.reserveCapacity(1 << 18)
        var lastReport = Date.distantPast

        for try await byte in bytes {
            try Task.checkCancellation()
            buffer.append(byte)
            if buffer.count >= 1 << 18 {
                try handle.write(contentsOf: buffer)
                downloaded += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                let now = Date()
                if now.timeIntervalSince(lastReport) > 0.15 {
                    lastReport = now
                    progress(DownloadProgress(
                        repoID: repoID, fileIndex: fileIndex, fileCount: fileCount,
                        currentFile: file, fileBytesDownloaded: downloaded, fileTotalBytes: totalBytes
                    ))
                }
            }
        }
        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
            downloaded += Int64(buffer.count)
        }
        progress(DownloadProgress(
            repoID: repoID, fileIndex: fileIndex, fileCount: fileCount,
            currentFile: file, fileBytesDownloaded: downloaded, fileTotalBytes: totalBytes
        ))
        try finalize(partial: partial, destination: destination)
    }

    private func finalize(partial: URL, destination: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) {
            try? fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: partial, to: destination)
    }

    private func destinationDirectory(for repoID: String) -> URL {
        modelsDirectory.appendingPathComponent(repoID.replacingOccurrences(of: "/", with: "--"), isDirectory: true)
    }

    static func isValidRepositoryID(_ value: String) -> Bool {
        guard !value.isEmpty, value.count < 200 else { return false }
        let pattern = #"^[A-Za-z0-9][A-Za-z0-9_.-]*(/[A-Za-z0-9][A-Za-z0-9_.-]*)?$"#
        return value.range(of: pattern, options: .regularExpression) != nil
    }

    static func encodedPath(_ path: String) -> String {
        path.split(separator: "/").map { segment in
            segment.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String(segment)
        }.joined(separator: "/")
    }
}