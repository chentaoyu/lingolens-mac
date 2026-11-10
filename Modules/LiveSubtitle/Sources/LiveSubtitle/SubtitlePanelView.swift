import AudioCapture
import Foundation
import SwiftUI

public struct SubtitlePanelView: View {
    @ObservedObject private var model: SubtitlePanelModel
    @ObservedObject private var store: SubtitleStore
    private let onClose: () -> Void
    private let onToggleClickThrough: () -> Void

    @State private var isHovering = false
    /// 是否跟随最新一行。只有用户主动滚动才会改变它；字幕变高（译文回填、原文折行）不算。
    @State private var isFollowing = true
    /// 「回到最新」倒计时剩余秒数；nil 表示没有在倒计时。
    @State private var autoResumeRemaining: Int?
    /// 自增表示请求跟随内容滚到底部（内容长高时）。
    @State private var followRequest = 0
    /// 自增表示请求带动画地回到底部（点按钮 / 倒计时结束）。
    @State private var resumeRequest = 0
    /// 不参与渲染的滚动跟踪状态，避免滚动过程每帧都触发界面刷新。
    @State private var scrollState = ScrollState()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                subtitleScroll
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
            if reduceMotion {
                isHovering = hovering
            } else {
                withAnimation(.easeInOut(duration: 0.18)) { isHovering = hovering }
            }
        }
        .environment(\.colorScheme, .dark)
    }

    private var lines: [SubtitleLine] {
        model.pausedLines ?? store.lines
    }

    /// 可滚动的字幕列表：默认跟随最新一行；用户往上翻后暂停跟随，
    /// 停手若干秒后自动回到最新，也可以点「回到最新」立刻回去。
    private var subtitleScroll: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(lines) { line in
                            row(for: line)
                                .id(line.id)
                        }
                        // 底部锚点：滚到它就等于停在最新一行。
                        Color.clear
                            .frame(height: 1)
                            .id(Self.bottomAnchor)
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.automatic)
                .onScrollGeometryChange(for: ScrollSnapshot.self) { geometry in
                    ScrollSnapshot(
                        offsetY: geometry.contentOffset.y,
                        contentHeight: geometry.contentSize.height,
                        containerHeight: geometry.containerSize.height
                    )
                } action: { _, snapshot in
                    handleGeometryChange(snapshot)
                }
                // 内容长高（译文回填、原文折行、改字号）后跟着滚到底，
                // 否则最新一行会停在视野外面。
                .onChange(of: followRequest) { _, _ in
                    scrollToBottom(proxy, animated: false, suppressWindow: Self.followScrollWindow)
                }
                // 点了「回到最新」或倒计时结束。
                .onChange(of: resumeRequest) { _, _ in
                    scrollToBottom(proxy, animated: !reduceMotion, suppressWindow: Self.resumeScrollWindow)
                }

                if !isFollowing {
                    resumeButton
                        .transition(.opacity)
                }
            }
            .onAppear {
                // 打开时直接停在最新一行。
                isFollowing = true
                scrollToBottom(proxy, animated: false, suppressWindow: 0.2)
            }
            .onDisappear {
                scrollState.settleTask?.cancel()
                stopAutoResume()
            }
        }
    }

    /// 往上翻之后给一个回到底部的入口，并显示自动回到最新的倒计时。
    private var resumeButton: some View {
        Button(action: requestResume) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.down.to.line")
                    .font(.system(size: 9, weight: .semibold))
                Text("回到最新")
                if let remaining = autoResumeRemaining {
                    Text("\(remaining)s")
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.white.opacity(0.18)))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.9))
        .padding(6)
        .help(autoResumeRemaining.map { "\($0) 秒后自动回到最新，点击立即回到" } ?? "回到最新一行")
        .accessibilityLabel("回到最新")
    }

    // MARK: - 跟随与自动回到底部

    /// 滚动几何变化。
    ///
    /// 关键点：内容高度变化（译文回填、原文折行、改字号）和窗口缩放都会改变
    /// “离底部的距离”，但它们不是用户在滚动，不能据此关闭跟随——旧实现就是
    /// 在这里被误判，导致用户没操作、自动滚动却停了。
    private func handleGeometryChange(_ snapshot: ScrollSnapshot) {
        let contentChanged = snapshot.contentHeight != scrollState.contentHeight
        let containerChanged = snapshot.containerHeight != scrollState.containerHeight
        scrollState.contentHeight = snapshot.contentHeight
        scrollState.containerHeight = snapshot.containerHeight

        if contentChanged || containerChanged {
            if isFollowing {
                followRequest &+= 1
            }
            return
        }

        // 程序化滚动的中间帧也会离开底部，别当成用户滚上去了。
        guard Date() >= scrollState.suppressUntil else { return }

        let distance = snapshot.contentHeight - snapshot.containerHeight - snapshot.offsetY
        // 内容还装不满一屏时不存在“滚上去看历史”，直接算在底部。
        let isScrollable = snapshot.contentHeight - snapshot.containerHeight > 1
        let atBottom = !isScrollable || distance <= Self.bottomTolerance

        scrollState.lastUserScrollAt = Date()
        if atBottom {
            stopAutoResume()
            isFollowing = true
        } else {
            // 用户又接着滚了：作废旧倒计时，等这次停手后重新计时。
            stopAutoResume()
            isFollowing = false
            watchScrollEnd()
        }
    }

    /// 等用户真正停手（含惯性滚动）后再开始自动回到底部的倒计时。
    private func watchScrollEnd() {
        guard scrollState.settleTask == nil else { return }
        scrollState.settleTask = Task { @MainActor in
            defer { scrollState.settleTask = nil }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(150))
                if Task.isCancelled { return }
                if Date().timeIntervalSince(scrollState.lastUserScrollAt) >= Self.scrollSettleDelay {
                    break
                }
            }
            guard !Task.isCancelled, !isFollowing else { return }
            startAutoResume()
        }
    }

    private func startAutoResume() {
        stopAutoResume()
        let seconds = Self.autoResumeDelay
        autoResumeRemaining = seconds
        scrollState.countdownTask = Task { @MainActor in
            for remaining in stride(from: seconds - 1, through: 0, by: -1) {
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
                autoResumeRemaining = remaining > 0 ? remaining : nil
            }
            guard !Task.isCancelled, !isFollowing else { return }
            requestResume()
        }
    }

    private func stopAutoResume() {
        scrollState.countdownTask?.cancel()
        scrollState.countdownTask = nil
        if autoResumeRemaining != nil {
            autoResumeRemaining = nil
        }
    }

    /// 回到最新一行并重新开始跟随。
    private func requestResume() {
        scrollState.settleTask?.cancel()
        scrollState.settleTask = nil
        stopAutoResume()
        isFollowing = true
        resumeRequest &+= 1
    }

    private static let bottomAnchor = "subtitle-bottom-anchor"
    /// 离底部这个范围内都算“在底部”。
    private static let bottomTolerance: CGFloat = 24
    /// 用户停手多久后算滚动结束。
    private static let scrollSettleDelay: TimeInterval = 0.5
    /// 往上翻后多久自动回到最新（秒）。
    private static let autoResumeDelay = 6
    /// 跟随内容滚动后忽略自身几何变化的窗口。
    private static let followScrollWindow: TimeInterval = 0.15
    /// 动画回到底部后忽略自身几何变化的窗口。
    private static let resumeScrollWindow: TimeInterval = 0.4

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool, suppressWindow: TimeInterval) {
        scrollState.suppressUntil = Date().addingTimeInterval(suppressWindow)
        let action = { proxy.scrollTo(Self.bottomAnchor, anchor: .bottom) }
        if animated {
            withAnimation(.easeOut(duration: 0.25)) { action() }
        } else {
            action()
        }
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

/// 滚动几何快照。用来区分“用户滚动”和“内容/窗口尺寸变化”。
private struct ScrollSnapshot: Equatable {
    var offsetY: CGFloat
    var contentHeight: CGFloat
    var containerHeight: CGFloat
}

/// 不参与渲染的滚动跟踪状态。
///
/// 这些字段每帧都会变，放进 `@State` 会让整个字幕列表反复求值；
/// 用引用类型收起来，只让真正影响界面的状态（isFollowing / 倒计时）触发刷新。
@MainActor
private final class ScrollState {
    var contentHeight: CGFloat = 0
    var containerHeight: CGFloat = 0
    /// 用户最后一次滚动的时间（含程序化滚动被排除后的判定）。
    var lastUserScrollAt = Date.distantPast
    /// 在此之前到达的几何变化来自程序化滚动，不算用户滚动。
    var suppressUntil = Date.distantPast
    var settleTask: Task<Void, Never>?
    var countdownTask: Task<Void, Never>?

    nonisolated init() {}
}
