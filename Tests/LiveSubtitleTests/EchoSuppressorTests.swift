import Foundation
import Testing
@testable import LiveSubtitle

@Suite("回声去重")
struct EchoSuppressorTests {
    @Test("和对方完全一样的内容判为回声")
    func identicalIsEcho() {
        var suppressor = EchoSuppressor()
        suppressor.noteOther("这个 API 的 latency 还是太高了")
        let result = suppressor.isEcho("这个 API 的 latency 还是太高了")
        #expect(result)
    }

    @Test("标点差异不影响判断")
    func punctuationInsensitive() {
        var suppressor = EchoSuppressor()
        suppressor.noteOther("deadline 是周五")
        let result = suppressor.isEcho("Deadline 是周五。")
        #expect(result)
    }

    @Test("完全不同的内容不是回声")
    func differentIsNotEcho() {
        var suppressor = EchoSuppressor()
        suppressor.noteOther("明天我们再看一下这个方案")
        let result = suppressor.isEcho("我先去开个会")
        #expect(!result)
    }

    @Test("超出时间窗不再比较")
    func expiresAfterWindow() {
        var suppressor = EchoSuppressor()
        let start = Date()
        suppressor.noteOther("这个方案还需要再确认", at: start)
        let inWindow = suppressor.isEcho("这个方案还需要再确认", at: start.addingTimeInterval(3))
        let outOfWindow = suppressor.isEcho("这个方案还需要再确认", at: start.addingTimeInterval(10))
        #expect(inWindow)
        #expect(!outOfWindow)
    }

    @Test("太短的文本不做判断，避免误杀")
    func ignoresVeryShortText() {
        var suppressor = EchoSuppressor()
        suppressor.noteOther("好")
        let result = suppressor.isEcho("好")
        #expect(!result)
    }

    @Test("相似度计算")
    func similarityMath() {
        #expect(EchoSuppressor.similarity("abcd", "abcd") == 1)
        #expect(EchoSuppressor.similarity("abcd", "wxyz") == 0)
        // 多一个字的同义句：相似但不至于判为回声。
        let partial = EchoSuppressor.similarity("这个方案很好", "这个方案非常好")
        #expect(partial > 0.3)
        #expect(partial < EchoSuppressor.threshold)
    }

    @Test("两路识别的标点/空格差异仍判为回声")
    func toleranceToFormatting() {
        var suppressor = EchoSuppressor()
        suppressor.noteOther("这个 API 的 latency 还是太高了。")
        let result = suppressor.isEcho("这个API的latency还是太高了")
        #expect(result)
    }
}
