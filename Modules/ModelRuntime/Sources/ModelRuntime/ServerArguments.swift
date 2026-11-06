import Foundation

/// 单个模型的进程级服务参数。
public struct ServerOptions: Sendable, Equatable, Codable {
    /// KV cache 量化位数，nil 表示使用 mlx-vlm 默认值。
    public var kvCacheBits: Int?
    /// 最大 KV 长度，nil 表示使用模型默认值。
    public var maxKVCacheLength: Int?
    /// 直接追加给 `mlx_vlm.server` 的额外参数，用于版本差异兜底。
    public var extraArguments: [String]

    public init(kvCacheBits: Int? = nil, maxKVCacheLength: Int? = nil, extraArguments: [String] = []) {
        self.kvCacheBits = kvCacheBits
        self.maxKVCacheLength = maxKVCacheLength
        self.extraArguments = extraArguments
    }
}

public enum ServerArguments {
    /// 注意：kv/max-kv 参数名依赖固定的 mlx-vlm 版本，升级版本时需同步核对；
    /// 若版本不支持，请改用 `extraArguments` 并清空这两个字段。
    public static func make(modelDirectory: URL, port: Int, options: ServerOptions) -> [String] {
        var arguments = [
            "-m", "mlx_vlm.server",
            "--model", modelDirectory.path,
            "--host", "127.0.0.1",
            "--port", String(port)
        ]
        if let bits = options.kvCacheBits {
            arguments.append(contentsOf: ["--kv-bits", String(bits)])
        }
        if let length = options.maxKVCacheLength {
            arguments.append(contentsOf: ["--max-kv-size", String(length)])
        }
        arguments.append(contentsOf: options.extraArguments)
        return arguments
    }
}
