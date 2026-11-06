import AppKit
import LLMClient
import ModelLibrary
import SelectionTranslate
import Settings
import SwiftUI

struct AppSettingsView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var showReinstallConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                generalSection
                audioSection
                scanRootsSection
                scenesSection
                serviceSection
                PermissionsSettingsView()
                runtimeSection
            }
            .padding(20)
        }
        .confirmationDialog(
            "重新安装 Python 运行时？",
            isPresented: $showReinstallConfirm,
            titleVisibility: .visible
        ) {
            Button("重新安装", role: .destructive) {
                Task { await environment.installRuntime(force: true) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("会删除现有虚拟环境并重新安装 mlx-vlm，已下载的模型不受影响。")
        }
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("通用")

            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("目标语言")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker(
                        "",
                        selection: Binding(
                            get: { environment.settings.general.targetLanguage },
                            set: { language in
                                environment.updateGeneral { $0.targetLanguage = language }
                            }
                        )
                    ) {
                        ForEach(TranslationPrompt.supportedTargetLanguages, id: \.id) { language in
                            Text(language.name).tag(language.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 180)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("划词快捷键")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HotkeyRecorder(
                        spec: Binding(
                            get: { environment.settings.general.hotkey },
                            set: { spec in
                                environment.updateGeneral { $0.hotkey = spec }
                            }
                        )
                    )
                }

                Spacer()
            }

            HStack(spacing: 14) {
                Toggle(
                    "开机启动",
                    isOn: Binding(
                        get: { environment.settings.general.launchAtLogin },
                        set: { toggleLaunchAtLogin($0) }
                    )
                )
                .toggleStyle(.switch)
                .controlSize(.small)

                Button("试一下划词翻译") {
                    environment.coordinator.trigger()
                }
                .controlSize(.small)

                Text("选中任意应用中的文字后按快捷键，浮窗会显示译文。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var audioSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("音频会话")
            Text("开始后按所选来源采集并实时转写；字幕浮窗可随时开关。")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 20) {
                Toggle("系统音频（对方）", isOn: audioBinding(\.captureSystemAudio))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Toggle("麦克风（我）", isOn: audioBinding(\.captureMicrophone))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Toggle("记录会议", isOn: audioBinding(\.recordMeetings))
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            HStack(spacing: 20) {
                languagePicker("对方语言", selection: audioBinding(\.otherLanguage))
                languagePicker("我的语言", selection: audioBinding(\.meLanguage))
                Spacer()
            }

            HStack(spacing: 10) {
                let audioActive = environment.audioSession.state == .running
                    || environment.audioSession.state == .starting
                Button(audioActive ? "停止音频会话" : "开始音频会话") {
                    Task {
                        if audioActive {
                            await environment.stopAudioSession()
                        } else {
                            await environment.startAudioSession()
                        }
                    }
                }
                .controlSize(.small)

                Text(environment.audioSession.statusText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("显示字幕浮窗") {
                    environment.subtitlePanel.show()
                }
                .controlSize(.small)

                Button(environment.subtitlePanel.isClickThrough ? "关闭点击穿透" : "开启点击穿透") {
                    environment.subtitlePanel.toggleClickThrough()
                }
                .controlSize(.small)
            }

            Divider()

            Text("字幕翻译")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                Toggle("翻译对方", isOn: subtitleBinding(\.other.translate))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                languagePicker("目标", selection: subtitleBinding(\.other.targetLanguage))

                Toggle("翻译我", isOn: subtitleBinding(\.me.translate))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                languagePicker("目标", selection: subtitleBinding(\.me.targetLanguage))
            }
        }
    }

    private func audioBinding<Value>(_ keyPath: WritableKeyPath<AudioSessionSettings, Value>) -> Binding<Value> {
        Binding(
            get: { environment.settings.audioSession[keyPath: keyPath] },
            set: { value in
                environment.updateAudioSession { $0[keyPath: keyPath] = value }
            }
        )
    }

    private func subtitleBinding<Value>(_ keyPath: WritableKeyPath<SubtitleSettings, Value>) -> Binding<Value> {
        Binding(
            get: { environment.settings.subtitle[keyPath: keyPath] },
            set: { value in
                environment.updateSubtitle { $0[keyPath: keyPath] = value }
            }
        )
    }

    private func languagePicker(_ title: String, selection: Binding<String>) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Picker("", selection: selection) {
                ForEach(TranslationPrompt.supportedTargetLanguages, id: \.id) { language in
                    Text(language.name).tag(language.id)
                }
            }
            .labelsHidden()
            .frame(width: 130)
        }
    }

    private var scanRootsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("扫描目录")
            Text("启动与点击“刷新”时会扫描这些目录中的 MLX 模型。")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                ForEach(environment.settings.scanRoots, id: \.self) { path in
                    HStack(spacing: 8) {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                        Text(abbreviatedPath(path))
                            .font(.system(size: 11, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button {
                            environment.removeScanRoot(path)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .help("移除该扫描目录")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)

                    if path != environment.settings.scanRoots.last {
                        Divider()
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.secondary.opacity(0.05))
            )

            HStack(spacing: 10) {
                Button("添加目录…") {
                    addScanRoot()
                }
                .controlSize(.small)

                Button("立即重新扫描") {
                    Task { await environment.refreshModels() }
                }
                .controlSize(.small)

                Spacer()
            }
        }
    }

    private func addScanRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "添加"
        if panel.runModal() == .OK {
            for url in panel.urls {
                environment.addScanRoot(url)
            }
        }
    }

    private func abbreviatedPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard path.hasPrefix(home) else { return path }
        return "~" + path.dropFirst(home.count)
    }

    private var scenesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("场景")
            Text("每个场景可使用常驻模型，或指定独立模型（首次请求时启动，空闲后按策略卸载）。")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(SceneID.allCases, id: \.self) { scene in
                SceneSettingsCard(scene: scene)
            }
        }
    }

    private var serviceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("服务参数")
            Text("按模型配置 KV cache 与空闲卸载时间，修改后点击“应用并重启”生效。")
                .font(.caption)
                .foregroundStyle(.secondary)

            let available = environment.models.filter(\.isAvailable)
            if available.isEmpty {
                Text("请先在“模型”页添加模型。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(available) { record in
                    ServiceSettingsRow(record: record)
                }
            }
        }
    }

    private var runtimeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("运行时")

            HStack(spacing: 12) {
                Image(systemName: environment.runtimeInstalled ? "checkmark.seal.fill" : "shippingbox")
                    .foregroundStyle(environment.runtimeInstalled ? Color.green : Color.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text(environment.runtimeInstalled ? "Python 环境已安装" : "Python 环境未就绪")
                        .font(.system(size: 12))
                    Text(environment.runtimeProgress.message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button("重新安装…") {
                    showReinstallConfirm = true
                }
                .controlSize(.small)

                Button("打开应用数据目录") {
                    environment.openAppSupportFolder()
                }
                .controlSize(.small)

                Button("打开日志文件夹") {
                    environment.openLogsFolder()
                }
                .controlSize(.small)
            }
        }
    }

    private func toggleLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLogin.set(enabled)
            environment.updateGeneral { $0.launchAtLogin = enabled }
        } catch {
            environment.lastError = "设置开机启动失败：\(error.localizedDescription)"
        }
    }
}

struct SectionTitle: View {
    private let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
    }
}

private struct SceneSettingsCard: View {
    @EnvironmentObject private var environment: AppEnvironment
    let scene: SceneID

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(scene.displayName)
                    .font(.system(size: 12, weight: .semibold))
                Text(scene.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("恢复默认参数") {
                    environment.updateScene(scene) { settings in
                        settings.parameters = scene.defaultParameters
                    }
                }
                .controlSize(.small)
            }

            HStack(spacing: 10) {
                Text("模型")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker(
                    "",
                    selection: Binding(
                        get: {
                            let settings = environment.settings.scene(scene)
                            return settings.useResidentModel ? "" : (settings.modelID ?? "")
                        },
                        set: { value in
                            environment.updateScene(scene) { settings in
                                if value.isEmpty {
                                    settings.useResidentModel = true
                                    settings.modelID = nil
                                } else {
                                    settings.useResidentModel = false
                                    settings.modelID = value
                                }
                            }
                        }
                    )
                ) {
                    Text("使用常驻模型").tag("")
                    ForEach(environment.models.filter(\.isAvailable)) { record in
                        Text(record.name).tag(record.id)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 320)

                Spacer()
            }

            ParameterEditor(
                parameters: Binding(
                    get: { environment.settings.scene(scene).parameters },
                    set: { parameters in
                        environment.updateScene(scene) { $0.parameters = parameters }
                    }
                )
            )
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.06))
        )
    }
}

private struct ParameterEditor: View {
    @Binding var parameters: GenerationParameters

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                labeledNumber("temperature", value: $parameters.temperature, width: 58)
                labeledNumber("top_p", value: $parameters.topP, width: 58)
                labeledInteger("max_tokens", value: $parameters.maxTokens, width: 66)
                labeledNumber("repetition_penalty", value: $parameters.repetitionPenalty, width: 58)
            }

            Toggle("thinking（思考过程）", isOn: $parameters.thinking)
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
    }

    private func labeledNumber(_ title: String, value: Binding<Double>, width: CGFloat) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            TextField("", value: value, format: .number.precision(.fractionLength(0...2)))
                .textFieldStyle(.roundedBorder)
                .frame(width: width)
        }
    }

    private func labeledInteger(_ title: String, value: Binding<Int>, width: CGFloat) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            TextField("", value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: width)
        }
    }
}

private struct ServiceSettingsRow: View {
    @EnvironmentObject private var environment: AppEnvironment
    let record: ModelRecord

    @State private var kvBits: String = ""
    @State private var maxKVLength: String = ""
    @State private var idleMinutes: Int = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(record.name)
                    .font(.system(size: 12, weight: .medium))
                Text(record.sourceLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("应用并重启") {
                    apply()
                }
                .controlSize(.small)
            }

            HStack(spacing: 16) {
                labeledText("KV 量化位数", text: $kvBits, width: 64, placeholder: "默认")
                labeledText("最大 KV 长度", text: $maxKVLength, width: 84, placeholder: "默认")
                HStack(spacing: 6) {
                    Text("空闲卸载(分钟)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TextField("", value: $idleMinutes, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 50)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.05))
        )
        .onAppear(perform: load)
    }

    private func labeledText(_ title: String, text: Binding<String>, width: CGFloat, placeholder: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .frame(width: width)
        }
    }

    private func load() {
        let service = environment.settings.service(for: record.id)
        kvBits = service.kvCacheBits.map(String.init) ?? ""
        maxKVLength = service.maxKVCacheLength.map(String.init) ?? ""
        idleMinutes = service.idleUnloadMinutes
    }

    private func apply() {
        environment.updateService(record.id) { service in
            service.kvCacheBits = Int(kvBits.trimmingCharacters(in: .whitespaces))
            service.maxKVCacheLength = Int(maxKVLength.trimmingCharacters(in: .whitespaces))
            service.idleUnloadMinutes = max(0, idleMinutes)
        }
        Task { await environment.applyServiceAndRestart(record) }
    }
}
