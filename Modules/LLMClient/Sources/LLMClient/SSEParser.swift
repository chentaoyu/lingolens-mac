import Foundation

public struct SSEEvent: Sendable, Equatable {
    public let event: String?
    public let data: String

    public init(event: String? = nil, data: String) {
        self.event = event
        self.data = data
    }
}

/// 增量 SSE 解析器：按行解析 `field: value`，空行派发事件。
public struct SSEParser: Sendable {
    private var buffer = ""
    private var dataLines: [String] = []
    private var eventName: String?

    public init() {}

    public mutating func consume(_ chunk: String) -> [SSEEvent] {
        buffer += chunk
        // Swift 把 "\r\n" 视作单个 Character，按行切分前先归一化为 "\n"。
        if buffer.contains("\r\n") {
            buffer = buffer.replacingOccurrences(of: "\r\n", with: "\n")
        }
        var events: [SSEEvent] = []
        while let newline = buffer.firstIndex(of: "\n") {
            var line = String(buffer[buffer.startIndex..<newline])
            buffer.removeSubrange(buffer.startIndex...newline)
            if line.hasSuffix("\r") { line.removeLast() }
            if let event = consumeLine(line) {
                events.append(event)
            }
        }
        return events
    }

    public mutating func finish() -> [SSEEvent] {
        var events: [SSEEvent] = []
        if !buffer.isEmpty {
            var line = buffer
            buffer.removeAll()
            if line.hasSuffix("\r") { line.removeLast() }
            if let event = consumeLine(line) {
                events.append(event)
            }
        }
        if let event = flush() {
            events.append(event)
        }
        return events
    }

    private mutating func consumeLine(_ line: String) -> SSEEvent? {
        if line.isEmpty {
            return flush()
        }
        if line.hasPrefix(":") {
            return nil
        }
        guard let colon = line.firstIndex(of: ":") else {
            return nil
        }
        let field = String(line[line.startIndex..<colon])
        var value = String(line[line.index(after: colon)...])
        if value.hasPrefix(" ") { value.removeFirst() }
        switch field {
        case "event":
            eventName = value
        case "data":
            dataLines.append(value)
        default:
            break
        }
        return nil
    }

    private mutating func flush() -> SSEEvent? {
        guard !dataLines.isEmpty else {
            eventName = nil
            return nil
        }
        let event = SSEEvent(event: eventName, data: dataLines.joined(separator: "\n"))
        dataLines.removeAll()
        eventName = nil
        return event
    }
}
