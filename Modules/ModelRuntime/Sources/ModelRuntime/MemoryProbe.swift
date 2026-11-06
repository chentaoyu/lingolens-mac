import Darwin
import Foundation

public protocol MemoryProbing: Sendable {
    /// 当前可用内存（free + inactive + speculative）。
    func availableMemoryBytes() -> UInt64
}

public struct SystemMemoryProbe: MemoryProbing {
    public init() {}

    public func availableMemoryBytes() -> UInt64 {
        var statistics = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { integerPointer in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, integerPointer, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            return ProcessInfo.processInfo.physicalMemory / 4
        }
        let pageSize = UInt64(getpagesize())
        let pages = UInt64(statistics.free_count)
            + UInt64(statistics.inactive_count)
            + UInt64(statistics.speculative_count)
        return pages * pageSize
    }
}

public enum ModelMemoryEstimator {
    /// 模型目录内所有 safetensors 文件的字节数。
    public static func weightsBytes(directory: URL) -> UInt64 {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: UInt64 = 0
        for case let url as URL in enumerator {
            guard url.pathExtension.lowercased() == "safetensors" else { continue }
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true,
                  let size = values.fileSize
            else { continue }
            total += UInt64(size)
        }
        return total
    }

    /// 权重 + 约 15% 运行时开销 + 512MB 余量。
    public static func estimatedMemoryBytes(directory: URL) -> UInt64 {
        let weights = weightsBytes(directory: directory)
        guard weights > 0 else { return 0 }
        return weights * 115 / 100 + 512 * 1024 * 1024
    }
}
