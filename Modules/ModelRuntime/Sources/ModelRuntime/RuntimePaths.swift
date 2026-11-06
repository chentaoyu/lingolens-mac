import Foundation

/// 应用运行期使用到的目录集合。
public struct RuntimePaths: Sendable, Hashable {
    public let appSupportDirectory: URL
    public let logsDirectory: URL
    public let modelsDirectory: URL
    public let runtimeDirectory: URL
    public let meetingsDirectory: URL

    public init(appSupportDirectory: URL, logsDirectory: URL) {
        self.appSupportDirectory = appSupportDirectory.standardizedFileURL
        self.logsDirectory = logsDirectory.standardizedFileURL
        self.modelsDirectory = self.appSupportDirectory.appendingPathComponent("models", isDirectory: true)
        self.runtimeDirectory = self.appSupportDirectory.appendingPathComponent("runtime", isDirectory: true)
        self.meetingsDirectory = self.appSupportDirectory.appendingPathComponent("meetings", isDirectory: true)
    }

    /// `~/Library/Application Support/LingoLens` 与 `~/Library/Logs/LingoLens`。
    public static func standard() -> RuntimePaths {
        let fileManager = FileManager.default
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        let logs = fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs", isDirectory: true)
        return RuntimePaths(
            appSupportDirectory: support.appendingPathComponent("LingoLens", isDirectory: true),
            logsDirectory: logs.appendingPathComponent("LingoLens", isDirectory: true)
        )
    }

    public var settingsFile: URL { appSupportDirectory.appendingPathComponent("settings.json", isDirectory: false) }
    public var libraryFile: URL { appSupportDirectory.appendingPathComponent("library.json", isDirectory: false) }
    public var pythonExecutable: URL { runtimeDirectory.appendingPathComponent("venv/bin/python3", isDirectory: false) }
    public var installationMarker: URL { runtimeDirectory.appendingPathComponent("installed.json", isDirectory: false) }
    public var pidRegistryFile: URL { runtimeDirectory.appendingPathComponent("servers.json", isDirectory: false) }

    /// 创建所有目录，幂等。
    public func prepare() throws {
        let fileManager = FileManager.default
        for directory in [appSupportDirectory, runtimeDirectory, modelsDirectory, meetingsDirectory, logsDirectory] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    public func logURL(forModel name: String) -> URL {
        logsDirectory.appendingPathComponent(Self.sanitizedFileComponent(name) + ".log", isDirectory: false)
    }

    public static func sanitizedFileComponent(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let mapped = name.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "-" }
        let result = String(mapped)
        return result.isEmpty ? "model" : result
    }
}
