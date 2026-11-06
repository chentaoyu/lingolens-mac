import AppKit
import LiveSubtitle
import LLMClient
import ModelLibrary
import SelectionTranslate
import Settings
import SwiftUI

struct AppSettingsView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var section: SettingsSection = .general
    @State private var showReinstallConfirm = false

    enum SettingsSection: String, CaseIterable, Identifiable {
        case general = "通用"
        case audio = "音频与字幕"
        case scenes = "场景"
        case models = "模型服务"
        case system = "权限与运行时"

        var id: Self { self }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $section) {
                ForEach(SettingsSection.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.vertical, 12)

            Divider()

            Group {
                switch section {
                case .general: generalForm
                case .audio: audioForm
                case .scenes: scenesPage
                case .models: modelsForm
                case .system: systemForm
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    // MARK: - 通用

    private var generalForm: some View {
        Form {
            Section("划词翻译") {
                Picker("目标语言", selection: generalBinding(\.targetLanguage)) {
                    languageOptions
                }
                LabeledContent("快捷键") {
                    HStack(spacing: 8) {
                        if !environment.coordinator.isHotkeyRegistered {
                            Label("注册失败，可能被占用", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        HotkeyRecorder(spec: generalBinding(\.hotkey))
                    }
                }
                LabeledContent("试一试") {
                    Button("打开翻译浮窗") { environment.coordinator.openManualPanel() }
                }
            }
            Section("启动") {
                Toggle("开机启动", isOn: Binding(
                    get: { environment.settings.general.launchAtLogin },
                    set: { toggleLaunchAtLogin($0) }
                ))
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - 音频与字幕

    private var audioForm: some View {
        Form {
            Section {
                Toggle("系统音频（对方）", isOn: audioBinding(\.captureSystemAudio))
                Toggle("麦克风（我）", isOn: audioBinding(\.captureMicrophone))
                Toggle("记录会议", isOn: audioBinding(\.recordMeetings))
                Picker("对方语言", selection: audioBinding(\.otherLanguage)) { languageOptions }
                Picker("我的语言", selection: audioBinding(\.meLanguage)) { languageOptions }
            } header: {
                Text("音频会话")
            } footer: {
                Text("会话开始时读取这些设置，运行中修改需停止后重新开始才生效。")
                    .foregroundStyle(.secondary)
            }

            Section("字幕翻译") {
                Toggle("翻译对方的发言", isOn: subtitleBinding(\.other.translate))
                Picker("对方译为", selection: subtitleBinding(\.other.targetLanguage)) { languageOptions }
                    .disabled(!environment.settings.subtitle.other.translate)
                Toggle("翻译我的发言", isOn: subtitleBinding(\.me.translate))
                Picker("我译为", selection: subtitleBinding(\.me.targetLanguage)) { languageOptions }
                    .disabled(!environment.settings.subtitle.me.translate)
            }

            Section("字幕浮窗") {
                Picker("字号", selection: Binding(
                    get: { SubtitleSizePreset(rawValue: environment.settings.subtitle.fontSize) ?? .standard },
                    set: { preset in environment.updateSubtitle { $0.fontSize = preset.rawValue } }
                )) {
                    ForEach(SubtitleSizePreset.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                LabeledContent("背景透明度") {
                    Slider(value: subtitleBinding(\.opacity), in: 0.4...1)
                        .frame(width: 200)
                }
                Toggle("显示字幕浮窗", isOn: Binding(
                    get: { environment.subtitlePanel.isVisible },
                    set: { _ in environment.subtitlePanel.toggleVisibility() }
                ))
                Toggle("点击穿透", isOn: Binding(
                    get: { environment.subtitlePanel.isClickThrough },
                    set: { _ in environment.subtitlePanel.toggleClickThrough() }
                ))
                .disabled(!environment.subtitlePanel.isVisible)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - 场景

    private var scenesPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("每个场景可使用常驻模型，或指定独立模型（首次请求时启动，空闲后按策略卸载）。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(SceneID.allCases, id: \.self) { scene in
                    SceneSettingsCard(scene: scene)
                }
            }
            .padding(20)
        }
    }

    // MARK: - 模型服务

    private var modelsForm: some View {
        Form {
            Section {
                ForEach(environment.settings.scanRoots, id: \.self) { path in
                    HStack {
                        Image(systemName: "folder").foregroundStyle(.secondary)
                        Text(abbreviatedPath(path))
                            .font(.system(size: 12, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button {
                            environment.removeScanRoot(path)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("移除该扫描目录")
                        .accessibilityLabel("移除扫描目录 \(abbreviatedPath(path))")
                    }
                }
                HStack {
                    Button("添加目录…") { addScanRoot() }
                    Button("立即重新扫描") { Task { await environment.refreshModels() } }
                }
            } header: {
                Text("扫描目录")
            } footer: {
                Text("启动与点击“刷新”时会扫描这些目录中的 MLX 模型。")
                    .foregroundStyle(.secondary)
            }

            Section {
                let available = environment.models.filter(\.isAvailable)
                if available.isEmpty {
                    Text("请先在“模型”页添加模型。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(available) { record in
                        ServiceSettingsRow(record: record)
                    }
                }
            } header: {
                Text("服务参数")
            } footer: {
                Text("按模型配置 KV cache 与空闲卸载时间，修改后点击“应用并重启”生效。")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - 权限与运行时

    private var systemForm: some View {
        Form {
            Section("权限") {
                PermissionsSettingsView()
            }
            Section("运行时") {
                LabeledContent {
                    Text(environment.runtimeProgress.message)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } label: {
                    Label(
                        environment.runtimeInstalled ? "Python 环境已安装" : "Python 环境未就绪",
                        systemImage: environment.runtimeInstalled ? "checkmark.seal.fill" : "shippingbox"
                    )
                    .foregroundStyle(environment.runtimeInstalled ? Color.green : Color.orange)
                }
                HStack {
                    Button("重新安装…") { showReinstallConfirm = true }
                    Button("打开应用数据目录") { environment.openAppSupportFolder() }
                    Button("打开日志文件夹") { environment.openLogsFolder() }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - 辅助

    private var languageOptions: some View {
        ForEach(TranslationPrompt.supportedTargetLanguages, id: \.id) { language in
            Text(language.name).tag(language.id)
        }
    }

    private func generalBinding<Value>(_ keyPath: WritableKeyPath<GeneralSettings, Value>) -> Binding<Value> {
        Binding(
            get: { environment.settings.general[keyPath: keyPath] },
            set: { value in environment.updateGeneral { $0[keyPath: keyPath] = value } }
        )
    }

    private func audioBinding<Value>(_ keyPath: WritableKeyPath<AudioSessionSettings, Value>) -> Binding<Value> {
        Binding(
            get: { environment.settings.audioSession[keyPath: keyPath] },
            set: { value in environment.updateAudioSession { $0[keyPath: keyPath] = value } }
        )
    }

    private func subtitleBinding<Value>(_ keyPath: WritableKeyPath<SubtitleSettings, Value>) -> Binding<Value> {
        Binding(
            get: { environment.settings.subtitle[keyPath: keyPath] },
            set: { value in environment.updateSubtitle { $0[keyPath: keyPath] = value } }
        )
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
