import Foundation
import Testing
@testable import LLMClient

@Suite("SSE 解析")
struct SSEParserTests {
    @Test("单个事件")
    func singleEvent() {
        var parser = SSEParser()
        let events = parser.consume("data: {\"a\":1}\n\n")
        #expect(events.count == 1)
        #expect(events.first?.data == "{\"a\":1}")
    }

    @Test("跨块的数据会拼接")
    func splitChunks() {
        var parser = SSEParser()
        #expect(parser.consume("data: hel").isEmpty)
        let events = parser.consume("lo\n\n")
        #expect(events.map(\.data) == ["hello"])
    }

    @Test("支持 CRLF 与多行 data")
    func crlfAndMultiline() {
        var parser = SSEParser()
        let events = parser.consume("event: message\r\ndata: line1\r\ndata: line2\r\n\r\n")
        #expect(events.count == 1)
        #expect(events.first?.event == "message")
        #expect(events.first?.data == "line1\nline2")
    }

    @Test("忽略注释行，finish 会派发剩余事件")
    func commentsAndFinish() {
        var parser = SSEParser()
        #expect(parser.consume(": ping\n").isEmpty)
        _ = parser.consume("data: tail")
        let events = parser.finish()
        #expect(events.map(\.data) == ["tail"])
    }
}
