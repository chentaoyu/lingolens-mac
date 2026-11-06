import Foundation

/// 内置运行时使用的固定版本。App 升级后若此值变化，会按需重装依赖。
public struct RuntimeSpec: Codable, Sendable, Equatable {
    public var pythonVersion: String
    public var mlxVLMVersion: String

    public init(pythonVersion: String = "3.12", mlxVLMVersion: String = "0.7.12") {
        self.pythonVersion = pythonVersion
        self.mlxVLMVersion = mlxVLMVersion
    }

    public static let `default` = RuntimeSpec()

    public var identifier: String {
        "python\(pythonVersion)-mlx-vlm\(mlxVLMVersion)"
    }

    /// 从 Bundle 中的 `RuntimeManifest.json` 读取；缺失时使用默认值。
    public static func fromBundle(_ bundle: Bundle = .main) -> RuntimeSpec {
        guard let url = bundle.url(forResource: "RuntimeManifest", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let spec = try? JSONDecoder().decode(RuntimeSpec.self, from: data)
        else { return .default }
        return spec
    }
}
