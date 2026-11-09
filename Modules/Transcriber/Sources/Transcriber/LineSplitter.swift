import Foundation

/// 把管道里到达的字节流按行切开，回调给上层。
///
/// ProcessCommandRunner 里有一份等价实现，但那是 ModelRuntime 的私有类型；
/// 这里单独放一个，供转写边车使用。
final class LineSplitter: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private let onLine: @Sendable (String) -> Void

    init(onLine: @escaping @Sendable (String) -> Void) {
        self.onLine = onLine
    }

    func consume(_ data: Data) {
        var lines: [String] = []
        lock.lock()
        buffer.append(data)
        while let index = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[buffer.startIndex..<index]
            buffer.removeSubrange(buffer.startIndex...index)
            if let line = String(data: lineData, encoding: .utf8) {
                lines.append(line)
            }
        }
        lock.unlock()
        for line in lines {
            onLine(line)
        }
    }

    /// 管道关闭时把没有换行结尾的残留也吐出来。
    func flush() {
        lock.lock()
        let remainder = buffer
        buffer.removeAll()
        lock.unlock()
        guard !remainder.isEmpty, let line = String(data: remainder, encoding: .utf8) else { return }
        onLine(line)
    }
}
