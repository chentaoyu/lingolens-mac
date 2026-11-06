import AppKit
import AudioCapture
import LiveSubtitle
import SelectionTranslate
import Settings
import SwiftUI

/// 菜单栏面板（`.window` 样式）：模型状态、音频会话控制与快捷入口。
struct MenuBarView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let toast = environment.toast {
                ToastBanner(
                    toast: toast,
                    onAction: { action in
                        closePanel()
                        environment.performToastAction(action)
                    },
                    onDismiss: environment.dismissToast
                )
            }

            if let error = environment.lastError {
                Button {
                    environment.clearError()
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.danger)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(error.title)
                                .font(.system(size: 11, weight: .semibold))
                            Text(error.message)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 4)
                        Text("知道了")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .background(Color.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("错误：\(error.title)，点击关闭提示")
            }

            modelStatus
            SessionCard(
                session: environment.audioSession,
                panel: environment.subtitlePanel,
                settingsStore: environment.settingsStore
            )
            Divider()
            links
        }
        .padding(14)
        .frame(width: 320)
    }

    private var modelStatus: some View {
        Button {
            open(.models)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "cpu")
                    .font(.title3)
                    .frame(width: 32, height: 32)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(environment.residentModel?.name ?? "未设置常驻模型")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Circle().fill(environment.residentStatusColor).frame(width: 6, height: 6)
                        Text(environment.statusSummary)
                            .lineLimit(1)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(environment.statusSummary)
        .accessibilityHint("打开模型页")
    }

    private var links: some View {
        VStack(spacing: 2) {
            MenuLinkButton(title: "划词翻译", systemImage: "character.bubble", shortcut: environment.hotkeyDisplay) {
                closePanel()
                // 关闭面板后让原应用重新获得焦点，再读取选中文字。
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(150))
                    environment.coordinator.trigger()
                }
            }
            MenuLinkButton(title: "打开主窗口", systemImage: "macwindow") {
                open(nil)
            }
            MenuLinkButton(title: "打开日志文件夹", systemImage: "doc.text.magnifyingglass") {
                closePanel()
                environment.openLogsFolder()
            }
            MenuLinkButton(title: "退出 LingoLens", systemImage: "power", shortcut: "⌘Q") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }

    private func open(_ tab: MainTab?) {
        closePanel()
        environment.showMainWindow(tab)
    }
}

/// `MenuBarExtra` 的 `.window` 样式没有公开的关闭接口，直接关闭当前面板窗口。
@MainActor
func closePanel() {
    NSApp.keyWindow?.close()
}

private struct SessionCard: View {
    @EnvironmentObject private var environment: AppEnvironment
    @ObservedObject var session: AudioSessionController
    @ObservedObject var panel: SubtitlePanelController
    @ObservedObject var settingsStore: SettingsStore

    private enum Source: String, CaseIterable {
        case system = "系统音频"
        case microphone = "麦克风"
        case both = "两者"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SessionButton()
                .controlSize(.large)
                .frame(maxWidth: .infinity)

            statusLine

            if session.state == .running {
                levelMeters
            }

            if panel.isVisible {
                subtitleLink
            }

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    label("音频源")
                    Picker("", selection: sourceBinding) {
                        ForEach(Source.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                GridRow {
                    label("对方语言")
                    languagePicker(\.otherLanguage)
                }
                GridRow {
                    label("我的语言")
                    languagePicker(\.meLanguage)
                }
            }
            .disabled(isActive)

            Toggle("记录会议", isOn: audioBinding(\.recordMeetings))
                .disabled(isActive)
            Toggle("显示字幕浮窗", isOn: Binding(
                get: { panel.isVisible },
                set: { _ in panel.toggleVisibility() }
            ))
            if panel.isVisible {
                Toggle("字幕点击穿透", isOn: Binding(
                    get: { panel.isClickThrough },
                    set: { _ in panel.toggleClickThrough() }
                ))
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .font(.system(size: 12))
    }

    @ViewBuilder
    private var statusLine: some View {
        switch session.state {
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.danger)
                .font(.caption)
        case .running, .starting:
            HStack(spacing: 6) {
                if session.isRecordingMeeting {
                    Circle().fill(Color.danger).frame(width: 6, height: 6)
                    Text("记录中 ·")
                }
                Text(session.statusText)
                    .lineLimit(2)
                Spacer()
                Text("停止后可改来源和语言")
                    .foregroundStyle(.tertiary)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        case .idle:
            EmptyView()
        }
    }

    /// 两路电平：让用户一眼确认「到底有没有采到声音」。
    private var levelMeters: some View {
        VStack(spacing: 5) {
            ForEach(AudioChannel.allCases, id: \.self) { channel in
                if session.activeLanguages[channel] != nil {
                    HStack(spacing: 8) {
                        Text(channel.displayName)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(channel.color)
                            .frame(width: 22, alignment: .leading)
                        AudioLevelMeter(
                            level: CGFloat(session.levels[channel] ?? 0),
                            tint: channel.color
                        )
                        .frame(maxWidth: 170, alignment: .leading)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .padding(.horizontal, 2)
    }

    /// 字幕浮窗已经在显示时，给一个「过去看一眼」的入口。
    private var subtitleLink: some View {
        Button {
            closePanel()
            panel.show()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "captions.bubble.fill")
                Text("字幕浮窗正在显示")
                Spacer()
                Text("查看浮窗")
                Image(systemName: "arrow.up.forward.app")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("把字幕浮窗移到最前面")
    }

    private var isActive: Bool {
        session.state == .running || session.state == .starting
    }

    private func label(_ text: String) -> some View {
        Text(text).foregroundStyle(.secondary)
    }

    private func languagePicker(_ keyPath: WritableKeyPath<AudioSessionSettings, String>) -> some View {
        Picker("", selection: audioBinding(keyPath)) {
            Text("自动识别").tag(AudioLanguageSettings.automatic)
            ForEach(TranslationPrompt.supportedTargetLanguages, id: \.id) { language in
                Text(language.name).tag(language.id)
            }
        }
        .labelsHidden()
    }

    private var sourceBinding: Binding<Source> {
        Binding(
            get: {
                let audio = settingsStore.settings.audioSession
                switch (audio.captureSystemAudio, audio.captureMicrophone) {
                case (true, false): return .system
                case (false, true): return .microphone
                default: return .both
                }
            },
            set: { source in
                settingsStore.update {
                    $0.audioSession.captureSystemAudio = source != .microphone
                    $0.audioSession.captureMicrophone = source != .system
                }
            }
        )
    }

    private func audioBinding<Value>(_ keyPath: WritableKeyPath<AudioSessionSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settingsStore.settings.audioSession[keyPath: keyPath] },
            set: { value in
                settingsStore.update { $0.audioSession[keyPath: keyPath] = value }
            }
        )
    }
}

/// 分段电平指示：亮起段数跟随电平，颜色沿用说话人配色。
private struct AudioLevelMeter: View {
    let level: CGFloat
    let tint: Color

    private let segments = 10

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<segments, id: \.self) { index in
                let threshold = CGFloat(index + 1) / CGFloat(segments)
                RoundedRectangle(cornerRadius: 1)
                    .fill(level >= threshold ? tint : Color.secondary.opacity(0.16))
                    .frame(height: 10)
            }
        }
        .frame(height: 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("音量 \(Int(level * 100))%")
    }
}

private struct MenuLinkButton: View {
    let title: String
    let systemImage: String
    var shortcut: String?
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .frame(width: 18)
                    .foregroundStyle(.secondary)
                Text(title)
                Spacer()
                if let shortcut {
                    Text(shortcut)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .font(.system(size: 13))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(isHovering ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(title)
    }
}
