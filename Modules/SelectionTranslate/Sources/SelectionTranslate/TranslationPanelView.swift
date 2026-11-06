import SwiftUI

public struct TranslationPanelView: View {
    @ObservedObject private var model: TranslationPanelModel
    private let onClose: () -> Void
    @FocusState private var editorFocused: Bool

    public init(model: TranslationPanelModel, onClose: @escaping () -> Void) {
        self.model = model
        self.onClose = onClose
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            languageRow
            source
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
        .animation(.easeInOut(duration: 0.18), value: model.phase)
        .animation(.easeInOut(duration: 0.18), value: model.isEditingSource)
        .onChange(of: model.isEditingSource) { _, editing in
            editorFocused = editing
        }
    }

    // MARK: - 头部

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "character.bubble.fill")
                .foregroundStyle(.tint)
            Text(model.isPinned ? "已固定" : "LingoLens 翻译")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                model.togglePin()
            } label: {
                Image(systemName: model.isPinned ? "pin.fill" : "pin")
            }
            .help(model.isPinned ? "取消固定（点外部会关闭）" : "固定浮窗（点外部不关闭）")
            .foregroundStyle(model.isPinned ? Color.accentColor : Color.secondary)

            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .help("关闭（Esc）")
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .font(.system(size: 12))
    }

    private var languageRow: some View {
        HStack(spacing: 8) {
            Text(sourceLabel)
                .foregroundStyle(.secondary)
            Image(systemName: "arrow.right")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Menu {
                Button("自动（按设置）") { model.setTarget(nil) }
                Divider()
                ForEach(TranslationPrompt.supportedTargetLanguages, id: \.id) { language in
                    Button(language.name) { model.setTarget(language.id) }
                }
            } label: {
                Text(targetLabel)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Spacer()
        }
        .font(.system(size: 11))
    }

    private var sourceLabel: String {
        guard let language = model.sourceLanguage else { return "自动检测" }
        return "检测到 " + TranslationPrompt.languageName(language)
    }

    private var targetLabel: String {
        guard !model.targetLanguage.isEmpty else { return model.targetOverride.map(TranslationPrompt.languageName) ?? "自动" }
        let name = TranslationPrompt.languageName(model.targetLanguage)
        return model.targetOverride == nil ? "\(name)（自动）" : name
    }

    // MARK: - 原文

    @ViewBuilder
    private var source: some View {
        if model.isEditingSource {
            TextEditor(text: $model.originalText)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .focused($editorFocused)
                .padding(6)
                .frame(minHeight: 54, maxHeight: 120)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )
                .overlay(alignment: .bottomTrailing) {
                    Text("⌘↩ 翻译")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .padding(6)
                }
        } else {
            Button {
                model.isEditingSource = true
            } label: {
                HStack(alignment: .top, spacing: 6) {
                    Text(model.originalText)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "pencil")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("点击编辑原文")
        }
    }

    // MARK: - 译文

    private var translation: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                switch model.phase {
                case .loading:
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("正在加载模型…")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                case .streaming:
                    Text("\(model.translatedText)\(Text("▍").foregroundStyle(.tint))")
                        .font(.system(size: 15))
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .finished where !model.translatedText.isEmpty:
                    Text(model.translatedText)
                        .font(.system(size: 15))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case let .failed(message):
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("翻译失败").font(.system(size: 13, weight: .semibold))
                            Text(message)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Button("重试") { model.retranslate() }
                                .controlSize(.small)
                        }
                    }
                default:
                    Text(model.placeholderText)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.vertical, 2)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - 底部

    private var footer: some View {
        HStack(spacing: 10) {
            Text(model.phase == .finished ? model.footer : "本机处理")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            Spacer()
            Button {
                model.retranslate()
            } label: {
                Label("重译", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut(.return, modifiers: .command)
            .help("重新翻译（⌘↩）")
            .disabled(model.originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button {
                model.copyTranslation()
            } label: {
                Label(model.didCopy ? "已复制" : "复制", systemImage: model.didCopy ? "checkmark" : "doc.on.doc")
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .help("复制译文（⇧⌘C）")
            .disabled(model.translatedText.isEmpty)
        }
        .buttonStyle(.borderless)
        .font(.system(size: 11))
        .labelStyle(.titleAndIcon)
    }
}
