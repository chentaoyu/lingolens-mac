import SwiftUI

public struct TranslationPanelView: View {
    @ObservedObject private var model: TranslationPanelModel
    private let onClose: () -> Void

    public init(model: TranslationPanelModel, onClose: @escaping () -> Void) {
        self.model = model
        self.onClose = onClose
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            editor
            Divider().opacity(0.4)
            translation
            footer
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
        .onExitCommand(perform: onClose)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "character.bubble.fill")
                .foregroundStyle(.tint)
            Text("划词翻译")
                .font(.system(size: 12, weight: .semibold))
            Spacer()
            Button {
                model.retranslate()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("重新翻译（⌘↩）")
            .keyboardShortcut(.return, modifiers: .command)

            Button {
                model.copyTranslation()
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .help("复制译文")
            .disabled(model.translatedText.isEmpty)

            Button {
                model.togglePin()
            } label: {
                Image(systemName: model.isPinned ? "pin.fill" : "pin")
            }
            .help(model.isPinned ? "取消固定（点外部不再关闭）" : "固定浮窗")
            .foregroundStyle(model.isPinned ? Color.accentColor : Color.secondary)

            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .help("关闭（Esc）")
        }
        .buttonStyle(.plain)
        .font(.system(size: 12))
    }

    private var editor: some View {
        TextEditor(text: $model.originalText)
            .font(.system(size: 13))
            .scrollContentBackground(.hidden)
            .padding(6)
            .frame(minHeight: 46, maxHeight: 110)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
            .overlay(alignment: .topTrailing) {
                if model.phase == .idle {
                    Text("⌘↩")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(6)
                }
            }
    }

    private var translation: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if model.placeholderText.isEmpty {
                    Text(model.translatedText)
                        .font(.system(size: 14))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(model.placeholderText)
                        .font(.system(size: 13))
                        .foregroundStyle(model.isFailure ? Color.red.opacity(0.8) : Color.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if model.isFailure {
                    Button("重试") {
                        model.retranslate()
                    }
                    .controlSize(.small)
                }
            }
            .padding(.vertical, 2)
        }
        .frame(maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            if case .loading = model.phase {
                ProgressView()
                    .controlSize(.mini)
            }
            Text(model.footer)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Text("Esc 关闭")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }
}
