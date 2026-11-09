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

    /// 内置的 GitHub 加速前缀。
    ///
    /// 第三方服务随时可能失效，顺序只表示「默认尝试次序」，实际会按测速结果重排；
    /// 出现失效时把可用的那个往前挪即可。
    public static let builtinMirrorPrefixes = [
        "https://ghfast.top/",
        "https://gh-proxy.com/"
    ]
}

/// 把 appcast 里的官方下载地址展开成候选列表。
///
/// 刻意**不做测速择优**：实测 GitHub 直连与部分镜像都是「小请求几百 KB/s、
/// 整包下载 504 gateway timeout」，用分块采样测速会稳定地选中那个下不完的源。
/// 因此按固定顺序依次尝试、失败换下一个，比任何测速都可靠。
public enum UpdateDownloadResolver {
    /// 候选地址（按尝试顺序排列，第一个是默认值）。
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
            // 镜像排在官方之前：GitHub 直连常常「小请求能通、整包下载 504」，
            // 探测阶段判断不准，所以让官方做兜底而不是首选。
            urls = UpdateDownloadSettings.builtinMirrorPrefixes.compactMap {
                customURL(official: official, template: $0 + "{url}")
            } + [official]
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

}
