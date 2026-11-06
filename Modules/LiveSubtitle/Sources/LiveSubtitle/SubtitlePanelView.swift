import AudioCapture
import SwiftUI

public struct SubtitlePanelView: View {
    @ObservedObject private var model: SubtitlePanelModel
    @ObservedObject private var store: SubtitleStore
    private let onClose: () -> Void
    private let onToggleClickThrough: () -> Void

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
        VStack(alignment: .leading, spacing: 8) {
            header

            if store.lines.isEmpty {
                Text("等待语音…（在菜单栏开始音频会话）")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(store.lines.suffix(5))) { line in
                        row(for: line)
                    }
                }
                Spacer(minLength: 0)
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
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "captions.bubble.fill")
                .foregroundStyle(.white.opacity(0.7))
            Text("LingoLens 字幕")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
            Button {
                onToggleClickThrough()
            } label: {
                Image(systemName: model.clickThrough ? "cursorarrow.rays" : "cursorarrow")
            }
            .help(model.clickThrough ? "关闭点击穿透" : "开启点击穿透（只显示不响应鼠标）")
            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .help("关闭字幕（菜单栏可重新打开）")
        }
        .buttonStyle(.plain)
        .font(.system(size: 11))
        .foregroundStyle(.white.opacity(0.7))
    }

    private func row(for line: SubtitleLine) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(line.channel.displayName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(channelColor(line.channel).opacity(0.75)))

            VStack(alignment: .leading, spacing: 3) {
                Text(line.text)
                    .font(.system(size: max(11, model.settings.fontSize * 0.58)))
                    .foregroundStyle(.white.opacity(line.isFinal ? 0.62 : 0.42))
                    .lineLimit(2)

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

    private func channelColor(_ channel: AudioChannel) -> Color {
        switch channel {
        case .me: return .blue
        case .other: return .green
        }
    }
}
