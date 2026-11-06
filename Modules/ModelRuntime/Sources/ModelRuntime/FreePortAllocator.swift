import Darwin
import Foundation

public enum FreePortAllocator {
    /// 让系统分配一个仅监听 127.0.0.1 的空闲端口。
    public static func allocate() throws -> Int {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw RuntimeError.portUnavailable }
        defer { close(descriptor) }

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0

        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                bind(descriptor, socketAddress, length)
            }
        }
        guard bindResult == 0 else { throw RuntimeError.portUnavailable }

        var bound = sockaddr_in()
        let nameResult = withUnsafeMutablePointer(to: &bound) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                getsockname(descriptor, socketAddress, &length)
            }
        }
        guard nameResult == 0 else { throw RuntimeError.portUnavailable }
        return Int(UInt16(bigEndian: bound.sin_port))
    }
}
