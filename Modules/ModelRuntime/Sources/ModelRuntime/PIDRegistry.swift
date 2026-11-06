import Darwin
import Foundation

/// 记录本 App 启动过的模型服务进程，用于下次启动时清理残留。
public struct PIDRegistry: Sendable {
    public struct Record: Codable, Sendable, Equatable {
        public var modelID: String
        public var pid: Int32
        public var startedAt: Date

        public init(modelID: String, pid: Int32, startedAt: Date) {
            self.modelID = modelID
            self.pid = pid
            self.startedAt = startedAt
        }
    }

    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func write(_ records: [Record]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(records) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    public func read() -> [Record] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([Record].self, from: data)) ?? []
    }

    /// 终止上次运行残留的模型服务进程，然后删除记录文件。
    public func terminateStale() {
        let records = read()
        guard !records.isEmpty else { return }
        for record in records where record.pid > 0 {
            guard kill(record.pid, 0) == 0 else { continue }
            guard let path = Self.executablePath(of: record.pid), Self.looksLikeModelServer(path) else { continue }
            kill(record.pid, SIGTERM)
        }
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// 同步终止所有记录的进程（用于 App 退出时无法 await 的场景）。
    public func terminateAll() {
        let records = read()
        for record in records where record.pid > 0 {
            guard kill(record.pid, 0) == 0 else { continue }
            guard let path = Self.executablePath(of: record.pid), Self.looksLikeModelServer(path) else { continue }
            kill(record.pid, SIGTERM)
        }
        try? FileManager.default.removeItem(at: fileURL)
    }

    public static func executablePath(of pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    public static func looksLikeModelServer(_ path: String) -> Bool {
        path.contains("mlx_vlm")
            || path.contains("LingoLens/runtime/venv/bin/python")
            || path.contains("LingoLens/runtime/venv/bin/")
    }
}
