import AudioCapture
import SwiftUI

public struct SubtitlePanelView: View {
    @ObservedObject private var model: SubtitlePanelModel
    @ObservedObject private var store: SubtitleStore
    private let onClose: () -> Void
    private let onToggleClickThrough: () -> Void

    @State private var isHovering = false

    public init(
        model: SubtitlePanelModel,
        store: SubtitleStore,
        onClose: @escaping () -> Void,
        onToggleClickThrough: @escaping () -> Void
    ) {
        self.model = model
        self.store = store
        self.onClose = onClose
        self.onToggleClickThrough = onToggleClickThrough
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            controlBar
            if lines.isEmpty {
                Text("等待语音…（在菜单栏开始音频会话）")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(lines.suffix(4)) { line in
                        row(for: line)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .animation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.24), value: lines.map(\.id))
                .animation(.easeInOut(duration: 0.18), value: lines)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(model.settings.opacity))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08))
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.18)) { isHovering = hovering }
        }
        .environment(\.colorScheme, .dark)
    }

    private var lines: [SubtitleLine] {
        model.pausedLines ?? store.lines
    }

    // MARK: - 控制条

    /// 平时只露出状态，悬停时显示完整控制；点击穿透时只能从菜单栏关闭穿透。
    private var controlBar: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(model.isPaused ? Color.orange : Color.red)
                .frame(width: 6, height: 6)
            Text(model.isPaused ? "已暂停" : "实时字幕")
                .font(.system(size: 11, weight: .semibold))
            if model.clickThrough {
                Label("点击穿透", systemImage: "cursorarrow.rays")
                    .font(.system(size: 10))
            }
            Spacer()
            if isHovering && !model.clickThrough {
                controls
                    .transition(.opacity)
            }
        }
        .foregroundStyle(.white.opacity(0.75))
        .frame(height: 22)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                model.togglePause()
            } label: {
                Image(systemName: model.isPaused ? "play.fill" : "pause.fill")
                    .iconHitArea()
            }
            .help(model.isPaused ? "继续滚动字幕" : "暂停滚动（转写不受影响）")
            .accessibilityLabel(model.isPaused ? "继续" : "暂停")

            HStack(spacing: 2) {
                ForEach(SubtitleSizePreset.allCases, id: \.self) { preset in
                    Button(preset.title) {
                        model.update { $0.fontSize = preset.rawValue }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(Color.white.opacity(currentPreset == preset ? 0.22 : 0))
                    )
                }
            }

            HStack(spacing: 4) {
                Image(systemName: "circle.lefthalf.filled")
                Slider(
                    value: Binding(
                        get: { model.settings.opacity },
                        set: { value in model.update { $0.opacity = value } }
                    ),
                    in: 0.4...1
                )
                .frame(width: 80)
                .controlSize(.mini)
                .accessibilityLabel("背景透明度")
            }
            .help("背景透明度")

            Button {
                onToggleClickThrough()
            } label: {
                Image(systemName: "cursorarrow.rays")
                    .iconHitArea()
            }
            .help("开启点击穿透（之后从菜单栏关闭）")
            .accessibilityLabel("开启点击穿透")

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .iconHitArea()
            }
            .help("关闭字幕（菜单栏可重新打开）")
            .accessibilityLabel("关闭字幕")
        }
        .buttonStyle(.plain)
        .font(.system(size: 11))
    }

    private var currentPreset: SubtitleSizePreset? {
        SubtitleSizePreset(rawValue: model.settings.fontSize)
    }

    // MARK: - 字幕行

    private func row(for line: SubtitleLine) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(line.channel.displayName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(channelColor(line.channel).opacity(0.85)))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(line.text)
                        .font(.system(size: max(11, model.settings.fontSize * 0.6)))
                        .foregroundStyle(.white.opacity(line.isFinal ? 0.62 : 0.4))
                        .lineLimit(2)
                    if !line.isFinal {
                        ListeningDots()
                    }
                }

                if let translation = line.translation, !translation.isEmpty {
                    Text(translation)
                        .font(.system(size: model.settings.fontSize, weight: .medium))
                        .foregroundStyle(.white)
                } else if line.failed {
                    Text("⚠ 翻译失败")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }
            }

            Spacer(minLength: 0)
        }
    }

    /// 颜色来自 App 的 Assets.xcassets（模块链接进 App 后从主 bundle 读取）。
    private func channelColor(_ channel: AudioChannel) -> Color {
        switch channel {
        case .me: return Color("SpeakerMe", bundle: .main)
        case .other: return Color("SpeakerOther", bundle: .main)
        }
    }
}

/// 未定稿句子后的“识别中”提示。
private struct ListeningDots: View {
    var body: some View {
        Image(systemName: "ellipsis")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white.opacity(0.5))
            .symbolEffect(.variableColor.iterative, options: .repeating)
    }
}

private extension View {
    /// 小图标按钮的点击区域扩大到 20×20。
    func iconHitArea() -> some View {
        frame(width: 20, height: 20).contentShape(Rectangle())
    }
}
