import Foundation

/// 模型列表的持久化存储（`library.json`）。
public actor ModelCatalog {
    private struct Storage: Codable {
        var version: Int
        var models: [ModelRecord]

        init(version: Int = 1, models: [ModelRecord]) {
            self.version = version
            self.models = models
        }
    }

    private let fileURL: URL
    private var records: [ModelRecord]

    public init(fileURL: URL) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let storage = try? JSONDecoder().decode(Storage.self, from: data) {
            self.records = storage.models
        } else {
            self.records = []
        }
    }

    public func all() -> [ModelRecord] {
        records
    }

    public func record(id: String) -> ModelRecord? {
        records.first { $0.id == id }
    }

    @discardableResult
    public func refreshAvailability() -> [ModelRecord] {
        for index in records.indices {
            records[index].isAvailable = ModelInspector.isModelDirectory(records[index].directoryURL)
        }
        persist()
        return records
    }

    /// 合并一次扫描结果：新增模型、更新信息、移除已消失的扫描项。
    @discardableResult
    public func syncScanned(candidates: [URL]) -> [ModelRecord] {
        let candidateURLs = candidates.map { $0.standardizedFileURL }
        let candidatePaths = Set(candidateURLs.map(\.path))

        for url in candidateURLs {
            let path = url.path
            let info = ModelInspector.inspect(directory: url)
            if let index = records.firstIndex(where: { $0.path == path }) {
                records[index].info = info
                records[index].isAvailable = true
                if records[index].name.isEmpty {
                    records[index].name = ModelInspector.displayName(for: url)
                }
            } else {
                records.append(ModelRecord(
                    id: path,
                    name: ModelInspector.displayName(for: url),
                    path: path,
                    source: .scanned,
                    addedAt: Date(),
                    info: info,
                    isAvailable: true
                ))
            }
        }

        records.removeAll { record in
            record.source == .scanned && !candidatePaths.contains(record.path)
        }
        persist()
        return records
    }

    @discardableResult
    public func importModel(at url: URL) throws -> ModelRecord {
        let standardized = url.standardizedFileURL
        guard ModelInspector.isModelDirectory(standardized) else {
            throw ModelLibraryError.notAModelDirectory(standardized.path)
        }
        if let existing = records.first(where: { $0.path == standardized.path }) {
            return existing
        }
        let record = ModelRecord(
            id: standardized.path,
            name: ModelInspector.displayName(for: standardized),
            path: standardized.path,
            source: .imported,
            addedAt: Date(),
            info: ModelInspector.inspect(directory: standardized),
            isAvailable: true
        )
        records.append(record)
        persist()
        return record
    }

    /// 下载完成后登记。
    @discardableResult
    public func registerDownloaded(at url: URL, name: String? = nil) -> ModelRecord {
        let standardized = url.standardizedFileURL
        if let existing = records.first(where: { $0.path == standardized.path }) {
            return existing
        }
        let record = ModelRecord(
            id: standardized.path,
            name: name ?? ModelInspector.displayName(for: standardized),
            path: standardized.path,
            source: .downloaded,
            addedAt: Date(),
            info: ModelInspector.inspect(directory: standardized),
            isAvailable: true
        )
        records.append(record)
        persist()
        return record
    }

    /// 删除：下载的模型删除文件，扫描 / 导入的仅移出列表。
    public func remove(id: String) throws {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        let record = records[index]
        if record.source == .downloaded {
            try? FileManager.default.removeItem(atPath: record.path)
        }
        records.remove(at: index)
        persist()
    }

    public func rename(id: String, to name: String) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        records[index].name = trimmed
        persist()
    }

    private func persist() {
        let storage = Storage(models: records)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(storage) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: .atomic)
    }
}
