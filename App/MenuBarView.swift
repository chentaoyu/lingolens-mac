import AppKit
import LiveSubtitle
import SelectionTranslate
import Settings
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        Button("划词翻译（\(environment.hotkeyDisplay)）") {
            environment.coordinator.trigger()
        }

        Button("打开主窗口") {
            openMainWindow()
        }

        Divider()

        AudioSessionMenuSection(
            session: environment.audioSession,
            panel: environment.subtitlePanel,
            settingsStore: environment.settingsStore,
            start: { Task { await environment.startAudioSession() } },
            stop: { Task { await environment.stopAudioSession() } },
            togglePanel: { environment.subtitlePanel.toggleVisibility() },
            toggleClickThrough: { environment.subtitlePanel.toggleClickThrough() }
        )

        Divider()

        Text(environment.statusSummary)

        Divider()

        Button("打开日志文件夹") {
            environment.openLogsFolder()
        }

        Button("退出 LingoLens") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func openMainWindow() {
        MainWindowController.shared.show()
    }
}

private struct AudioSessionMenuSection: View {
    @ObservedObject var session: AudioSessionController
    @ObservedObject var panel: SubtitlePanelController
    @ObservedObject var settingsStore: SettingsStore

    let start: () -> Void
    let stop: () -> Void
    let togglePanel: () -> Void
    let toggleClickThrough: () -> Void

    var body: some View {
        Button(session.state == .running ? "停止音频会话" : "开始音频会话") {
            if session.state == .running || session.state == .starting {
                stop()
            } else {
                start()
            }
        }

        Button(panel.isVisible ? "隐藏字幕浮窗" : "显示字幕浮窗") {
            togglePanel()
        }

        if panel.isVisible {
            Button(panel.isClickThrough ? "关闭字幕点击穿透" : "开启字幕点击穿透") {
                toggleClickThrough()
            }
        }

        Menu("音频来源") {
            Toggle("系统音频（对方）", isOn: audioBinding(\.captureSystemAudio))
            Toggle("麦克风（我）", isOn: audioBinding(\.captureMicrophone))
            Toggle("记录会议", isOn: audioBinding(\.recordMeetings))
        }

        Menu("每路语言") {
            Picker("对方", selection: audioBinding(\.otherLanguage)) {
                ForEach(TranslationPrompt.supportedTargetLanguages, id: \.id) { language in
                    Text(language.name).tag(language.id)
                }
            }
            Picker("我", selection: audioBinding(\.meLanguage)) {
                ForEach(TranslationPrompt.supportedTargetLanguages, id: \.id) { language in
                    Text(language.name).tag(language.id)
                }
            }
        }

        Text(session.statusText)

        if session.isRecordingMeeting {
            Text("正在记录会议")
        }
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
