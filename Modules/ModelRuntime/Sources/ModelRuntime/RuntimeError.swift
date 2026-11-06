import Foundation

/// 运行时（Python 环境与模型服务进程）相关的错误。
public enum RuntimeError: Error, LocalizedError, Equatable, Sendable {
    case uvNotFound
    case commandFailed(command: String, exitCode: Int32, output: String)
    case pythonMissing(path: String)
    case portUnavailable
    case launchFailed(reason: String)
    case readinessTimedOut(seconds: TimeInterval)
    case insufficientMemory(requiredBytes: UInt64, availableBytes: UInt64)
    case modelStopped
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .uvNotFound:
            return "未找到可用的 uv，请重新安装 LingoLens，或在设置中指定 uv 路径。"
        case let .commandFailed(command, exitCode, output):
            let tail = output.suffix(600)
            return "命令 `\(command)` 执行失败（退出码 \(exitCode)）：\(tail)"
        case let .pythonMissing(path):
            return "Python 环境不完整：缺少 \(path)"
        case .portUnavailable:
            return "无法分配本地端口。"
        case let .launchFailed(reason):
            return "模型服务启动失败：\(reason)"
        case let .readinessTimedOut(seconds):
            return "模型服务在 \(Int(seconds)) 秒内未就绪。"
        case let .insufficientMemory(required, available):
            return "内存不足：预计需要 \(formatBytes(required))，当前可用 \(formatBytes(available))。"
        case .modelStopped:
            return "模型服务已停止。"
        case .cancelled:
            return "操作已取消。"
        }
    }
}

public func formatBytes(_ bytes: UInt64) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
}
