import AppKit
import LiveSubtitle
import LLMClient
import Meetings
import ModelLibrary
import ModelRuntime
import SelectionTranslate
import Settings
import SwiftUI

struct AppSettingsView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var section: SettingsSection = .general
    @State private var showReinstallConfirm = false
    @State private var templates: [MinutesTemplate] = []
    @State private var showTemplateSheet = false
    @AppStorage("showInDock") private var showInDock = false

    enum SettingsSection: String, CaseIterable, Identifiable {
        case general = "通用"
        case audio = "音频与字幕"
        case scenes = "场景"
        case templates = "纪要模板"
        case models = "模型服务"
        case system = "权限与运行时"

        var id: Self { self }
    }

    var body: some View {
        // 与原型一致：设置内部再分一列导航，避免顶部 6 段 segmented 在窄窗口里挤成一团。
        HStack(spacing: 0) {
            List(selection: sectionBinding) {
                ForEach(SettingsSection.allCases) { item in
                    Text(item.rawValue)
                        .tag(item)
                }
            }
            .listStyle(.sidebar)
            // 子导航不再铺灰色侧边栏材质：白底，和右侧内容只靠中间这条线分割。
            .scrollContentBackground(.hidden)
            .frame(width: 150)
            .background(Color(nsColor: .textBackgroundColor))

            Divider()

            Group {
                switch section {
                case .general: generalForm
                case .audio: audioForm
                case .scenes: scenesPage
                case .templates: templatesPage
                case .models: modelsForm
                case .system: systemForm
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task { templates = await environment.templates() }
        .onChange(of: showTemplateSheet) { _, showing in
            if !showing {
                Task { templates = await environment.templates() }
            }
        }
        .sheet(isPresented: $showTemplateSheet) {
            MinutesTemplateSheet()
                .environmentObject(environment)
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
            Text("会删除现有虚拟环境并重新安装 mlx-vlm，已下载的模型和依赖缓存不受影响。")
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
                                .foregroundStyle(Color.warning)
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
                Toggle("在 Dock 中显示", isOn: dockBinding)
            }
            Section("帮助") {
                LabeledContent("首次使用引导") {
                    Button("重新查看") { environment.presentOnboarding() }
                }
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
                Picker("对方语言", selection: audioBinding(\.otherLanguage)) { audioLanguageOptions }
                Picker("我的语言", selection: audioBinding(\.meLanguage)) { audioLanguageOptions }
            } header: {
                Text("音频会话")
            } footer: {
                Text("会话开始时读取这些设置，运行中修改需停止后重新开始才生效。选「自动识别」时会同时加载中英两套语音模型，按每句话的置信度自动判断语言。")
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("目标语言", selection: subtitleBinding(\.targetLanguage)) { languageOptions }
                Toggle("翻译对方的发言", isOn: subtitleBinding(\.other.translate))
                Toggle("翻译我的发言", isOn: subtitleBinding(\.me.translate))
            } header: {
                Text("字幕翻译")
            } footer: {
                Text("识别出的语言和目标语言相同时只显示原文，不再翻译（例如中文会议里不会出现「中文译中文」）。")
                    .foregroundStyle(.secondary)
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

    // MARK: - 纪要模板

    private var templatesPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("生成纪要时使用的提示词模板，会议页可以随时切换。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(templates) { template in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Text(template.name)
                                .font(.system(size: 12, weight: .semibold))
                            if template.id == MinutesTemplate.standardID {
                                TagBadge(text: "内置", color: .secondary)
                            }
                            Spacer()
                        }
                        Text(template.prompt)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                }

                Button {
                    showTemplateSheet = true
                } label: {
                    Label("管理模板…", systemImage: "square.and.pencil")
                }
                .padding(.top, 4)
            }
            .padding(20)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
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
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(environment.runtimeProgress.message)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        if let detail = environment.runtimeProgress.detail {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .lineLimit(2)
                        }
                    }
                } label: {
                    Label(
                        environment.runtimeInstalled ? "Python 环境已安装" : "Python 环境未就绪",
                        systemImage: environment.runtimeInstalled ? "checkmark.seal.fill" : "shippingbox"
                    )
                    .foregroundStyle(environment.runtimeInstalled ? Color.success : Color.warning)
                }
                if environment.isInstallingRuntime {
                    if let fraction = environment.runtimeProgress.fraction {
                        ProgressView(value: fraction)
                    } else {
                        ProgressView().progressViewStyle(.linear)
                    }
                }
                HStack {
                    if environment.isInstallingRuntime {
                        Button("取消安装") { environment.cancelRuntimeInstall() }
                    } else if environment.runtimeInstalled {
                        Button("重新安装…") { showReinstallConfirm = true }
                    } else {
                        Button("安装运行时…") { Task { await environment.installRuntime() } }
                    }
                    Button("打开应用数据目录") { environment.openAppSupportFolder() }
                    Button("打开日志文件夹") { environment.openLogsFolder() }
                }
            }
            Section {
                Picker("下载源", selection: runtimeBinding(\.packageSource)) {
                    ForEach(PackageIndexSource.allCases, id: \.self) { source in
                        Text(source.displayName).tag(source)
                    }
                }
                if environment.settings.runtime.packageSource == .custom {
                    TextField(
                        "索引地址",
                        text: runtimeBinding(\.customIndexURL),
                        prompt: Text("https://example.com/pypi/simple/")
                    )
                }
                TextField(
                    "代理",
                    text: runtimeBinding(\.proxyURL),
                    prompt: Text("http://127.0.0.1:7890（可选）")
                )
            } header: {
                Text("依赖下载")
            } footer: {
                Text("首次安装需要下载约 220MB 依赖。默认优先国内镜像，失败后自动回退官方 PyPI；代理会传给安装进程（留空则直连）。以上设置在下一次安装/重装时生效。")
                    .foregroundStyle(.secondary)
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

    /// 识别语言多一个「自动识别」选项（内部值 "auto"）。
    @ViewBuilder
    private var audioLanguageOptions: some View {
        Text("自动识别").tag(AudioLanguageSettings.automatic)
        languageOptions
    }

    private var sectionBinding: Binding<SettingsSection?> {
        Binding(
            get: { section },
            set: { if let value = $0 { section = value } }
        )
    }

    /// Dock 显隐是进程级状态，不进设置文件，切换后立即生效。
    private var dockBinding: Binding<Bool> {
        Binding(
            get: { showInDock },
            set: { value in
                showInDock = value
                NSApp.setActivationPolicy(value ? .regular : .accessory)
            }
        )
    }

    private func generalBinding<Value>(_ keyPath: WritableKeyPath<GeneralSettings, Value>) -> Binding<Value> {
        Binding(
            get: { environment.settings.general[keyPath: keyPath] },
            set: { value in environment.updateGeneral { $0[keyPath: keyPath] = value } }
        )
    }

    private func runtimeBinding<Value>(_ keyPath: WritableKeyPath<RuntimeInstallSettings, Value>) -> Binding<Value> {
        Binding(
            get: { environment.settings.runtime[keyPath: keyPath] },
            set: { value in environment.updateRuntime { $0[keyPath: keyPath] = value } }
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
            environment.reportMessage(
                "设置开机启动失败：\(error.localizedDescription)",
                title: "无法修改开机启动",
                code: "LAUNCH_AT_LOGIN"
            )
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
