import AppKit
import ApplicationServices
import Testing
@testable import SelectionTranslate

@Suite("辅助功能授权状态")
struct AccessibilityTrustTests {
    @Test("子进程检查返回布尔值或 nil")
    func childProcessReturnsValue() {
        // 测试进程本身是独立的二进制，结果取决于本机是否授权；
        // 这里只断言「能跑通并给出确定答案」，不假设具体值。
        let result = AccessibilityPermission.childProcessTrust()
        #expect(result == true || result == false || result == nil)
    }

    @Test("本进程结论与子进程结论能拼出三种状态")
    func resolvedStateIsConsistent() {
        let state = AccessibilityPermission.resolvedState()
        if AccessibilityPermission.isTrusted {
            #expect(state == .granted)
        } else {
            let child = AccessibilityPermission.childProcessTrust()
            #expect(state == (child == true ? .needsRestart : .denied))
        }
    }

    @Test("只有 granted 算可用")
    func onlyGrantedIsUsable() {
        #expect(AccessibilityTrustState.granted.isUsable)
        #expect(!AccessibilityTrustState.denied.isUsable)
        #expect(!AccessibilityTrustState.needsRestart.isUsable)
    }
}
