import Foundation

/// App 侧最小诊断日志：与 TranscriptionLog 同目录（`~/Library/Logs/LingoLens/app.log`）。
/// 菜单栏应用没有控制台，录音落盘这类后台动作出问题只能靠文件排查。
enum AppLog {
    private static let maxBytes = 512 * 1024
    private static let lock = NSLock()
    nonisolated(unsafe) private static var prepared = false

    static let url: URL = {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/LingoLens", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("app.log")
    }()

    static func write(_ message: String) {
        lock.lock()
        let needsPrepare = !prepared
        prepared = true
        lock.unlock()

        if needsPrepare {
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            if (size ?? 0) > maxBytes {
                try? FileManager.default.removeItem(at: url)
            }
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        guard let data = "[\(formatter.string(from: Date()))] \(message)\n".data(using: .utf8) else { return }

        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }
}
