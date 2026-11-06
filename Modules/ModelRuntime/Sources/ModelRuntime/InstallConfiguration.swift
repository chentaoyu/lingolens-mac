import Foundation

/// 依赖包下载源。
///
/// 默认 `automatic`：优先使用国内镜像，单个源失败后自动回退官方 PyPI，
/// 避免首次安装时直连 `pypi.org` 长时间卡住。
public enum PackageIndexSource: String, Codable, CaseIterable, Sendable {
    case automatic
    case aliyun
    case tsinghua
    case tencent
    case official
    case custom

    public var displayName: String {
        switch self {
        case .automatic: return "自动（国内镜像优先）"
        case .aliyun: return "阿里云"
        case .tsinghua: return "清华大学"
        case .tencent: return "腾讯云"
        case .official: return "官方 PyPI（需代理或海外网络）"
        case .custom: return "自定义"
        }
    }

    /// 内置源地址；`automatic` 与 `custom` 由 `InstallConfiguration` 决定。
    var builtinURL: URL? {
        switch self {
        case .aliyun: return URL(string: "https://mirrors.aliyun.com/pypi/simple/")
        case .tsinghua: return URL(string: "https://pypi.tuna.tsinghua.edu.cn/simple/")
        case .tencent: return URL(string: "https://mirrors.cloud.tencent.com/pypi/simple/")
        case .official: return InstallConfiguration.officialIndexURL
        case .automatic, .custom: return nil
        }
    }
}

/// 首次安装 Python 环境时的网络参数。
public struct InstallConfiguration: Sendable, Equatable {
    public static let officialIndexURL = URL(string: "https://pypi.org/simple/")!

    public var source: PackageIndexSource
    public var customIndexURL: String
    public var proxyURL: String
    /// 单次请求超时（秒）。默认 60，避免慢速连接一直挂着。
    public var httpTimeoutSeconds: Int
    /// 单次请求重试次数。
    public var httpRetries: Int

    public init(
        source: PackageIndexSource = .automatic,
        customIndexURL: String = "",
        proxyURL: String = "",
        httpTimeoutSeconds: Int = 60,
        httpRetries: Int = 5
    ) {
        self.source = source
        self.customIndexURL = customIndexURL
        self.proxyURL = proxyURL
        self.httpTimeoutSeconds = httpTimeoutSeconds
        self.httpRetries = httpRetries
    }

    public static let `default` = InstallConfiguration()

    /// 首选索引地址；自定义源非法时返回 nil。
    public var primaryIndexURL: URL? {
        switch source {
        case .automatic:
            return PackageIndexSource.aliyun.builtinURL
        case .custom:
            let trimmed = customIndexURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: trimmed),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https",
                  url.host?.isEmpty == false
            else { return nil }
            return url
        default:
            return source.builtinURL
        }
    }

    /// 依次尝试的索引列表；按顺序重试，前一个失败才用下一个。
    /// 明确选择官方源时不再回退，避免用户以为走了官方其实又连了镜像。
    public var indexAttempts: [URL?] {
        guard let primary = primaryIndexURL else { return [Self.officialIndexURL] }
        if primary.absoluteString == Self.officialIndexURL.absoluteString { return [primary] }
        if source == .official { return [primary] }
        return [primary, Self.officialIndexURL]
    }

    /// 传给 uv 子进程的网络相关环境变量。
    public var uvEnvironment: [String: String] {
        var environment: [String: String] = [
            "UV_HTTP_TIMEOUT": String(max(10, httpTimeoutSeconds)),
            "UV_HTTP_RETRIES": String(max(0, httpRetries)),
            "UV_CONCURRENT_DOWNLOADS": "8",
            // 使用系统钥匙串里的根证书，企业代理/自签名证书环境更容易通过。
            "UV_NATIVE_TLS": "1"
        ]
        let proxy = proxyURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !proxy.isEmpty {
            for key in ["HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "http_proxy", "https_proxy", "all_proxy"] {
                environment[key] = proxy
            }
        }
        return environment
    }

    /// 当前首选源的展示名（用于进度文案）。
    public var primarySourceDescription: String {
        primaryIndexURL?.host ?? source.displayName
    }
}
