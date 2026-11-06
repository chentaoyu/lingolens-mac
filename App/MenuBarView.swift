import AppKit
import LiveSubtitle
import SelectionTranslate
import Settings
import SwiftUI

/// 菜单栏面板（`.window` 样式）：模型状态、音频会话控制与快捷入口。
struct MenuBarView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                .foregroundStyle(.red)
                .font(.caption)
        case .running, .starting:
            HStack(spacing: 6) {
                if session.isRecordingMeeting {
                    Circle().fill(.red).frame(width: 6, height: 6)
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

    private var isActive: Bool {
        session.state == .running || session.state == .starting
    }

    private func label(_ text: String) -> some View {
        Text(text).foregroundStyle(.secondary)
    }

    private func languagePicker(_ keyPath: WritableKeyPath<AudioSessionSettings, String>) -> some View {
        Picker("", selection: audioBinding(keyPath)) {
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
