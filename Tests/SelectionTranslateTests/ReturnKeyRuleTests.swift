import AppKit
import Testing
@testable import SelectionTranslate

@Suite("回车提交规则")
struct ReturnKeyRuleTests {
    @Test("单独按回车立即提交")
    func plainReturn() {
        #expect(ReturnKeyRule.submits(keyCode: 36, modifiers: []))
        #expect(ReturnKeyRule.submits(keyCode: 76, modifiers: []))
    }

    @Test("带组合键的回车不直接提交")
    func modifiedReturn() {
        #expect(!ReturnKeyRule.submits(keyCode: 36, modifiers: .shift))
        #expect(!ReturnKeyRule.submits(keyCode: 36, modifiers: .command))
        #expect(!ReturnKeyRule.submits(keyCode: 36, modifiers: .option))
        #expect(!ReturnKeyRule.submits(keyCode: 36, modifiers: .control))
    }

    @Test("大小写锁定与小键盘标记不影响提交")
    func ignorableFlags() {
        #expect(ReturnKeyRule.submits(keyCode: 36, modifiers: [.capsLock, .function]))
        #expect(ReturnKeyRule.submits(keyCode: 76, modifiers: [.numericPad]))
    }

    @Test("其它按键不提交")
    func otherKeys() {
        #expect(!ReturnKeyRule.submits(keyCode: 53, modifiers: []))
        #expect(!ReturnKeyRule.submits(keyCode: 49, modifiers: []))
    }

    @Test("⇧↩ 与 ⌥↩ 插入换行")
    func newlineModifiers() {
        #expect(ReturnKeyRule.insertsNewline(modifiers: .shift))
        #expect(ReturnKeyRule.insertsNewline(modifiers: .option))
        #expect(!ReturnKeyRule.insertsNewline(modifiers: []))
        #expect(!ReturnKeyRule.insertsNewline(modifiers: .command))
    }
}
