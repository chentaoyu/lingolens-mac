import AppKit
import SwiftUI

/// 原文编辑框：单独按 ↩ 立即翻译，⇧↩ / ⌥↩ 换行，Esc 关闭浮窗。
///
/// SwiftUI 的 `TextEditor` 把回车固定当换行，拿不到「回车即提交」，
/// 这里换成 `NSTextView` 自己接管按键，顺带支持输入法候选上屏。
struct SourceTextEditor: NSViewRepresentable {
    @Binding var text: String
    /// 进入编辑态时自动把焦点交给输入框，打开浮窗即可直接打字。
    var isFocused: Bool
    var onSubmit: () -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay

        // 给一个初始尺寸，避免文档视图宽度/高度为 0 时首屏排版异常。
        let textView = SubmitOnReturnTextView(frame: NSRect(x: 0, y: 0, width: 380, height: 60))
        textView.delegate = context.coordinator
        textView.font = .systemFont(ofSize: 13)
        textView.textColor = .labelColor
        textView.drawsBackground = false
        textView.focusRingType = .none
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 0, height: 1)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.string = text
        textView.wantsFocus = isFocused
        textView.onSubmit = onSubmit
        textView.onCancel = onCancel
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? SubmitOnReturnTextView else { return }
        textView.onSubmit = onSubmit
        textView.onCancel = onCancel
        if textView.string != text {
            textView.string = text
        }
        textView.wantsFocus = isFocused
        if isFocused, textView.window?.firstResponder !== textView {
            // 浮窗刚创建时视图可能还没进窗口，延后一拍再要焦点。
            Task { @MainActor in
                guard let window = textView.window,
                      window.firstResponder !== textView
                else { return }
                window.makeFirstResponder(textView)
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SourceTextEditor

        init(parent: SourceTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView,
                  parent.text != textView.string
            else { return }
            parent.text = textView.string
        }
    }
}

/// 回车即提交的文本视图。
final class SubmitOnReturnTextView: NSTextView {
    var onSubmit: (() -> Void)?
    var onCancel: (() -> Void)?
    /// 编辑态下视图进窗口后自动接管键盘。
    var wantsFocus = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard wantsFocus,
              let window,
              window.firstResponder !== self,
              window.isVisible
        else { return }
        window.makeFirstResponder(self)
    }

    override func insertNewline(_ sender: Any?) {
        // 输入法正在选词时，回车先让候选上屏。
        guard !hasMarkedText() else {
            super.insertNewline(sender)
            return
        }
        let modifiers = NSApp.currentEvent?.modifierFlags ?? []
        // ⇧↩ / ⌥↩ 仍然插入换行，方便手动输入多行原文。
        guard !ReturnKeyRule.insertsNewline(modifiers: modifiers), let onSubmit else {
            super.insertNewline(sender)
            return
        }
        onSubmit()
    }

    override func insertLineBreak(_ sender: Any?) {
        super.insertNewline(sender)
    }

    override func cancelOperation(_ sender: Any?) {
        guard let onCancel else {
            super.cancelOperation(sender)
            return
        }
        onCancel()
    }
}
