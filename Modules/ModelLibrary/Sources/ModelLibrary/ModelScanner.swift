import Foundation

public struct ModelScanner: Sendable {
    public let maxDepth: Int

    public init(maxDepth: Int = 6) {
        self.maxDepth = maxDepth
    }

    /// 递归扫描给定根目录，返回符合 MLX 模型特征的目录。
    public func scan(roots: [URL]) -> [URL] {
        var found: [URL] = []
        var seen = Set<String>()

        for root in roots {
            let root = root.standardizedFileURL
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                continue
            }
            walk(root, depth: 0, rootPath: root.path, found: &found, seen: &seen)
        }
        return found.sorted { ModelInspector.displayName(for: $0) < ModelInspector.displayName(for: $1) }
    }

    private func walk(_ directory: URL, depth: Int, rootPath: String, found: inout [URL], seen: inout Set<String>) {
        guard depth <= maxDepth else { return }
        let path = directory.standardizedFileURL.path
        guard !seen.contains(path) else { return }
        seen.insert(path)

        if ModelInspector.looksLikeMLXModel(directory: directory) {
            found.append(directory)
            return
        }

        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        for child in contents {
            let values = try? child.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true else { continue }
            let name = child.lastPathComponent
            if name == "blobs" || name == ".git" || name == "refs" { continue }
            walk(child, depth: depth + 1, rootPath: rootPath, found: &found, seen: &seen)
        }
    }
}
