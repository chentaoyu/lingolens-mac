import Foundation

/// 从 uv 的非交互输出里提取的安装活动。
public struct InstallActivity: Sendable, Equatable {
    /// uv 解析出的待安装包总数（`Resolved N packages`）。
    public var totalPackages: Int?
    /// 已经开始下载的包。
    public var startedPackages: Int
    /// 已经下载完成的包。
    public var downloadedPackages: Int
    /// 已经写进虚拟环境的包（` + name==version` 行）。
    public var installedPackages: Int
    /// 已知包的下载体积合计。
    public var knownBytes: Int
    /// 已完成下载的包体积合计。
    public var downloadedBytes: Int
    /// 最近一个开始下载的包及其体积。
    public var currentPackage: String?
    public var currentPackageBytes: Int?

    public init(
        totalPackages: Int? = nil,
        startedPackages: Int = 0,
        downloadedPackages: Int = 0,
        installedPackages: Int = 0,
        knownBytes: Int = 0,
        downloadedBytes: Int = 0,
        currentPackage: String? = nil,
        currentPackageBytes: Int? = nil
    ) {
        self.totalPackages = totalPackages
        self.startedPackages = startedPackages
        self.downloadedPackages = downloadedPackages
        self.installedPackages = installedPackages
        self.knownBytes = knownBytes
        self.downloadedBytes = downloadedBytes
        self.currentPackage = currentPackage
        self.currentPackageBytes = currentPackageBytes
    }

    public static let idle = InstallActivity()
}

/// 解析 uv 输出。uv 在非终端环境下的典型输出：
///
/// ```
/// Using Python 3.12.13 environment at: …
/// Resolved 73 packages in 1.33s
/// Downloading mlx-metal (74.5MiB)
///  Downloaded pygments
/// Prepared 73 packages in 2.1s
/// Installed 73 packages in 412ms
///  + uvicorn==0.54.0
/// ```
public struct InstallOutputParser: Sendable {
    public private(set) var activity = InstallActivity.idle
    public private(set) var didFail = false
    public private(set) var didFinish = false

    private var sizes: [String: Int] = [:]
    private var started: Set<String> = []
    private var completed: Set<String> = []
    private var installedLines = 0

    public init() {}

    public mutating func consume(_ rawLine: String) {
        let line = rawLine
            .replacingOccurrences(of: "\r", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else { return }

        if line.hasPrefix("error:") || line.hasPrefix("cause:") {
            didFail = true
        } else if line.hasPrefix("Resolved ") {
            activity.totalPackages = Self.leadingNumber(in: line.dropFirst("Resolved ".count))
                ?? activity.totalPackages
        } else if line.hasPrefix("Downloaded ") {
            let name = String(line.dropFirst("Downloaded ".count)).trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { completed.insert(name) }
        } else if line.hasPrefix("Downloading ") {
            if let (name, bytes) = Self.downloadDescriptor(String(line.dropFirst("Downloading ".count))) {
                started.insert(name)
                if let bytes { sizes[name] = bytes }
                activity.currentPackage = name
                activity.currentPackageBytes = bytes
            }
        } else if line.hasPrefix("Prepared ") || line.hasPrefix("Installed ") {
            didFinish = true
            if let total = Self.leadingNumber(in: line) {
                activity.totalPackages = activity.totalPackages ?? total
            }
            activity.installedPackages = max(activity.installedPackages, activity.totalPackages ?? 0)
        } else if line.hasPrefix("+") && line.dropFirst().trimmingCharacters(in: .whitespaces).contains("==") {
            installedLines += 1
        }
        flush()
    }

    /// 每行解析后重算汇总值（包数量级很小，成本可忽略）。
    mutating func flush() {
        activity.startedPackages = started.count
        activity.downloadedPackages = completed.count
        activity.installedPackages = max(activity.installedPackages, min(installedLines, activity.totalPackages ?? installedLines))
        activity.knownBytes = sizes.values.reduce(0, +)
        activity.downloadedBytes = completed.compactMap { sizes[$0] }.reduce(0, +)
    }

    /// `mlx-metal (74.5MiB)` → (`mlx-metal`, 78_118_912)
    static func downloadDescriptor(_ text: String) -> (String, Int?)? {
        guard let open = text.lastIndex(of: "("), text.hasSuffix(")") else {
            let name = text.trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? nil : (name, nil)
        }
        let name = String(text[text.startIndex..<open]).trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        let sizeText = String(text[text.index(after: open)..<text.index(before: text.endIndex)])
        return (name, byteCount(from: sizeText))
    }

    static func byteCount(from text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let units: [(String, Double)] = [
            ("GiB", 1024 * 1024 * 1024), ("MiB", 1024 * 1024), ("KiB", 1024),
            ("GB", 1_000_000_000), ("MB", 1_000_000), ("KB", 1_000), ("B", 1)
        ]
        for (suffix, scale) in units where trimmed.hasSuffix(suffix) {
            let numberPart = trimmed.dropLast(suffix.count).trimmingCharacters(in: .whitespaces)
            guard let value = Double(numberPart) else { return nil }
            return Int(value * scale)
        }
        return Int(trimmed)
    }

    static func leadingNumber(in text: some StringProtocol) -> Int? {
        let digits = text.drop(while: { $0 == " " }).prefix(while: { $0.isNumber })
        return Int(digits)
    }
}
