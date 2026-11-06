import Foundation

/// 更新包（dmg）的下载源。
///
/// GitHub Releases 的下载在国内经常失败，这里允许走第三方加速前缀或自建 CDN。
public enum UpdateDownloadSource: String, Codable, CaseIterable, Sendable {
    /// 测速后选最快的可用源，失败自动换源。
    case automatic
    /// 只用 GitHub 官方地址。
    case official
    /// 只用自定义地址。
    case custom

    public var displayName: String {
        switch self {
        case .automatic: return "自动（测速选最快）"
        case .official: return "仅官方 GitHub"
        case .custom: return "自定义地址"
        }
    }
}

public struct UpdateDownloadSettings: Codable, Sendable, Equatable {
    public var source: UpdateDownloadSource
    /// 自定义地址模板：含 `{url}` 时替换成完整官方地址（镜像式），
    /// 否则按「前缀 + 文件名」拼接（自建 CDN 式）。
    public var customURLTemplate: String

    public init(source: UpdateDownloadSource = .automatic, customURLTemplate: String = "") {
        self.source = source
        self.customURLTemplate = customURLTemplate
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        source = (try? container.decodeIfPresent(UpdateDownloadSource.self, forKey: .source)) ?? .automatic
        customURLTemplate = (try? container.decodeIfPresent(String.self, forKey: .customURLTemplate)) ?? ""
    }

    /// 内置的 GitHub 加速前缀。第三方服务，随时可能失效，所以只作为可选/兜底。
    public static let builtinMirrorPrefixes = [
        "https://gh-proxy.com/",
        "https://ghfast.top/"
    ]
}

/// 把 appcast 里的官方下载地址展开成候选列表，并按测速结果挑选。
public enum UpdateDownloadResolver {
    /// 低于这个速度视为不可用。
    public static let minimumBytesPerSecond: Double = 30 * 1024
    /// 镜像要比官方快这么多倍才值得切换，避免为了 10% 的提速走第三方。
    public static let mirrorAdvantage: Double = 1.5

    /// 候选地址（按偏好排序，第一个是默认值）。
    public static func candidates(official: URL, settings: UpdateDownloadSettings) -> [URL] {
        var urls: [URL] = []

        switch settings.source {
        case .official:
            urls = [official]
        case .custom:
            if let custom = customURL(official: official, template: settings.customURLTemplate) {
                urls = [custom, official]
            } else {
                urls = [official]
            }
        case .automatic:
            urls = [official] + UpdateDownloadSettings.builtinMirrorPrefixes.compactMap {
                customURL(official: official, template: $0 + "{url}")
            }
        }

        var unique: [URL] = []
        for url in urls where !unique.contains(where: { $0.absoluteString == url.absoluteString }) {
            unique.append(url)
        }
        return unique.isEmpty ? [official] : unique
    }

    /// 模板展开：含 `{url}` 走镜像拼接，否则走 CDN 前缀 + 文件名。
    public static func customURL(official: URL, template: String) -> URL? {
        let trimmed = template.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let expanded: String
        if trimmed.contains("{url}") {
            expanded = trimmed.replacingOccurrences(of: "{url}", with: official.absoluteString)
        } else {
            let prefix = trimmed.hasSuffix("/") ? trimmed : trimmed + "/"
            expanded = prefix + official.lastPathComponent
        }

        guard let url = URL(string: expanded),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host?.isEmpty == false
        else { return nil }
        return url
    }

    /// 在候选里挑一个：优先官方，镜像必须明显更快才切换；都不达标时用第一个候选。
    public static func choose(
        candidates: [URL],
        measuredBytesPerSecond: [URL: Double],
        official: URL
    ) -> URL {
        let usable = candidates.filter { (measuredBytesPerSecond[$0] ?? 0) >= minimumBytesPerSecond }
        guard let best = usable.max(by: {
            (measuredBytesPerSecond[$0] ?? 0) < (measuredBytesPerSecond[$1] ?? 0)
        }) else {
            return candidates.first ?? official
        }

        let officialSpeed = measuredBytesPerSecond[official] ?? 0
        if best.absoluteString != official.absoluteString,
           officialSpeed >= minimumBytesPerSecond,
           (measuredBytesPerSecond[best] ?? 0) < officialSpeed * mirrorAdvantage {
            return official
        }
        return best
    }
}
