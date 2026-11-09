import AppKit
import Combine
import Foundation
import LiveSubtitle
import LLMClient
import Meetings
import ModelLibrary
import ModelRuntime
import SceneChat
import SelectionTranslate
import Settings

/// 应用级依赖容器：模型目录、运行时、服务进程、设置与划词翻译。
@MainActor
final class AppEnvironment: ObservableObject {
    static let shared = AppEnvironment()

    let paths: RuntimePaths
    let settingsStore: SettingsStore
    let pythonEnvironment: PythonEnvironment
    let serverPool: ServerPool
    let catalog: ModelCatalog
    let scanner: ModelScanner
    let downloader: HFDownloader
    let llmClient: LocalLLMClient
    let sceneChat: SceneChatService
    let translationService: TranslationService
    let coordinator: SelectionTranslationCoordinator
    let subtitleStore: SubtitleStore
    let subtitlePanel: SubtitlePanelController
    let subtitleTranslation: SubtitleTranslationController
    let meetingStore: MeetingStore
    let templateStore: MinutesTemplateStore
    let minutesGenerator: MinutesGenerator
    let audioSession: AudioSessionController
    /// 模型下载进度：模型页与下载面板共用。
    let downloadState = ModelDownloadState()

    @Published private(set) var settings: AppSettings
    @Published private(set) var models: [ModelRecord] = []
    @Published private(set) var servers: [ServerSnapshot] = []
    @Published private(set) var runtimeProgress = InstallProgress(phase: .idle, message: "尚未准备运行时")
    @Published private(set) var runtimeInstalled = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var isInstallingRuntime = false
    @Published private(set) var meetingsRevision = 0
    /// Whisper 模型下载状态。
    @Published private(set) var isDownloadingSpeechModel = false
    @Published private(set) var speechModelProgress: SpeechModelInstaller.Progress?
    @Published private(set) var speechModelInstalled = false
    @Published private(set) var lastError: AppError?
    /// 主窗口当前页；菜单栏等入口可直接跳转。
    @Published var mainTab: MainTab = .home
    /// 跳到会议页时要选中的会议。
    @Published var focusMeetingID: String?
    /// 操作回执（例如会话结束后的「会议已保存」）。
    @Published private(set) var toast: AppToast?
    /// 首次启动引导是否展示中。
    @Published var isOnboardingPresented = false
    /// 有新的会议记录但用户还没打开会议页，侧边栏显示一个小圆点。
    @Published var hasUnseenMeetings = false

    /// 引导完成标记；AppDelegate 在首次启动时据此决定要不要弹引导。
    nonisolated static let didFinishOnboardingKey = "LingoLens.didFinishOnboarding"

    private var started = false
    private var toastTask: Task<Void, Never>?
    private var statusTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        let paths = RuntimePaths.standard()
        try? paths.prepare()
        self.paths = paths

        let settingsStore = SettingsStore(fileURL: paths.settingsFile)
        self.settingsStore = settingsStore
        self.settings = settingsStore.settings

        let python = PythonEnvironment(
            paths: paths,
            spec: RuntimeSpec.fromBundle(),
            configuration: settingsStore.settings.runtime.installConfiguration
        )
        self.pythonEnvironment = python
        self.serverPool = ServerPool(paths: paths, python: python)
        self.catalog = ModelCatalog(fileURL: paths.libraryFile)
        self.scanner = ModelScanner()
        self.downloader = HFDownloader(modelsDirectory: paths.modelsDirectory)
        self.llmClient = LocalLLMClient()
        self.sceneChat = SceneChatService(
            client: llmClient,
            pool: serverPool,
            settingsStore: settingsStore,
            catalog: catalog
        )
        self.translationService = TranslationService(
            chat: sceneChat,
            settingsStore: settingsStore
        )
        self.coordinator = SelectionTranslationCoordinator(
            service: translationService,
            settingsStore: settingsStore
        )

        let subtitleStore = SubtitleStore()
        self.subtitleStore = subtitleStore
        self.subtitlePanel = SubtitlePanelController(
            store: subtitleStore,
            settingsStore: settingsStore
        )
        self.subtitleTranslation = SubtitleTranslationController(
            chat: sceneChat,
            settingsStore: settingsStore,
            store: subtitleStore
        )
        self.meetingStore = MeetingStore(root: paths.meetingsDirectory)
        self.templateStore = MinutesTemplateStore(
            fileURL: paths.appSupportDirectory.appendingPathComponent("minutes-templates.json")
        )
        self.minutesGenerator = MinutesGenerator(
            chat: sceneChat,
            settingsStore: settingsStore
        )
        self.audioSession = AudioSessionController(
            settingsStore: settingsStore,
            subtitleStore: subtitleStore,
            translation: subtitleTranslation,
            meetingStore: meetingStore,
            paths: paths
        )

        settingsStore.$settings
            .sink { [weak self] newSettings in
                self?.settings = newSettings
            }
            .store(in: &cancellables)

        // 下载源/代理只影响「下一次安装」，设置变化时同步给运行时。
        settingsStore.$settings
            .map(\.runtime.installConfiguration)
            .removeDuplicates()
            .sink { configuration in
                Task { await python.update(configuration: configuration) }
            }
            .store(in: &cancellables)

        audioSession.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        subtitlePanel.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        downloadState.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        audioSession.onSessionFinished = { [weak self] in
            self?.meetingsRevision += 1
            self?.hasUnseenMeetings = true
        }

        observeRuntimeProgress()
    }

    // MARK: - 生命周期

    func start() {
        guard !started else { return }
        started = true
        coordinator.start()

        // 以系统实际状态校准“开机启动”开关（用户可能在系统设置里改动过）。
        let loginItemEnabled = LaunchAtLogin.isEnabled
        if settings.general.launchAtLogin != loginItemEnabled {
            updateGeneral { $0.launchAtLogin = loginItemEnabled }
        }

        Task { @MainActor in
            await refreshModels()
            await refreshSpeechModelState()
            await installRuntimeIfNeeded()
            await restoreResidentModel()
            await serverPool.startIdleTimer()
        }
        startStatusLoop()
    }

    func shutdown() async {
        statusTask?.cancel()
        statusTask = nil
        await audioSession.stop()
        settingsStore.saveNow()
        await serverPool.shutdown()
    }

    // MARK: - 音频会话 / 字幕

    func startAudioSession() async {
        subtitlePanel.show()
        await audioSession.start()
        if case .failed = audioSession.state {
            subtitlePanel.hide()
        }
    }

    func stopAudioSession() async {
        guard let meeting = await audioSession.stop() else { return }
        showToast(
            AppToast(
                title: "会议已保存",
                subtitle: "「\(meeting.title)」的转写已保存，可以立即生成纪要。",
                actionTitle: "查看会议",
                action: .openMeeting(meeting.id)
            )
        )
    }

    // MARK: - 首次启动引导

    func presentOnboarding() {
        isOnboardingPresented = true
    }

    func finishOnboarding() {
        UserDefaults.standard.set(true, forKey: Self.didFinishOnboardingKey)
        isOnboardingPresented = false
    }

    // MARK: - 操作回执

    func showToast(_ toast: AppToast, autoDismissAfter seconds: Double = 6) {
        toastTask?.cancel()
        self.toast = toast
        toastTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    func dismissToast() {
        toastTask?.cancel()
        toastTask = nil
        toast = nil
    }

    func performToastAction(_ action: AppToast.Action) {
        dismissToast()
        switch action {
        case let .openMeeting(id):
            showMainWindow(.meetings, meetingID: id)
        }
    }

    // MARK: - 会议

    func loadMeetings() async -> [MeetingSummary] {
        (try? await meetingStore.list()) ?? []
    }

    func loadMeeting(id: String) async -> MeetingDetail? {
        try? await meetingStore.load(id: id)
    }

    func updateTranscript(meetingID: String, entryID: UUID, text: String) async {
        try? await meetingStore.updateEntry(meetingID: meetingID, entryID: entryID, text: text)
    }

    func saveMinutes(_ text: String, meetingID: String) async {
        try? await meetingStore.saveMinutes(text, for: meetingID)
    }

    func renameMeeting(id: String, title: String) async {
        try? await meetingStore.updateTitle(id: id, title: title)
    }

    func deleteMeeting(id: String) async {
        try? await meetingStore.delete(id: id)
    }

    func templates() async -> [MinutesTemplate] {
        await templateStore.all()
    }

    func addTemplate(name: String, prompt: String) async -> MinutesTemplate {
        await templateStore.add(name: name, prompt: prompt)
    }

    // MARK: - 运行时

    private func observeRuntimeProgress() {
        Task { @MainActor in
            for await progress in await pythonEnvironment.progressStream() {
                self.runtimeProgress = progress
                if progress.phase == .ready {
                    self.runtimeInstalled = true
                }
            }
        }
    }

    func installRuntimeIfNeeded() async {
        guard !runtimeInstalled else { return }
        await installRuntime(force: false)
    }

    /// 取消正在进行的安装（用户点「取消」或退出前）。
    func cancelRuntimeInstall() {
        Task { await pythonEnvironment.cancelInstall() }
    }

    /// 语音引擎与领域词表。
    func updateSpeech(_ mutate: (inout SpeechSettings) -> Void) {
        settingsStore.update { settings in
            mutate(&settings.speech)
        }
    }

    /// 刷新「Whisper 模型是否已就绪」。
    func refreshSpeechModelState() async {
        speechModelInstalled = SpeechModelInstaller(paths: paths).isInstalled
    }

    /// 从魔搭下载 Whisper 模型（约 464 MB）。
    func downloadSpeechModel() async {
        guard !isDownloadingSpeechModel else { return }
        isDownloadingSpeechModel = true
        defer {
            isDownloadingSpeechModel = false
            speechModelProgress = nil
        }
        do {
            let installer = SpeechModelInstaller(paths: paths)
            try await installer.install { progress in
                Task { @MainActor in
                    self.speechModelProgress = progress
                }
            }
            await refreshSpeechModelState()
            showToast(AppToast(title: "Whisper 模型已就绪", subtitle: "可在「音频会话」里切换引擎"))
        } catch {
            report(error, title: "Whisper 模型下载失败", code: "SPEECH_MODEL", actions: [
                AppError.Action("重试", isPrimary: true) {
                    Task { await self.downloadSpeechModel() }
                }
            ])
        }
    }

    func updateUpdateSettings(_ mutate: (inout UpdateDownloadSettings) -> Void) {
        settingsStore.update { settings in
            mutate(&settings.update)
        }
    }

    func updateRuntime(_ mutate: (inout RuntimeInstallSettings) -> Void) {
        settingsStore.update { settings in
            mutate(&settings.runtime)
        }
    }

    func installRuntime(force: Bool = false) async {
        guard !isInstallingRuntime else { return }
        isInstallingRuntime = true
        defer { isInstallingRuntime = false }
        do {
            if force {
                try await pythonEnvironment.reset()
                runtimeInstalled = false
            }
            _ = try await pythonEnvironment.ensureInstalled()
            runtimeInstalled = true
            runtimeProgress = InstallProgress(phase: .ready, message: "运行时已就绪", fraction: 1)
        } catch {
            runtimeInstalled = false
            runtimeProgress = InstallProgress(phase: .failed, message: error.localizedDescription)
            report(error, title: "运行时安装失败", code: "RUNTIME_INSTALL", actions: [
                AppError.Action("查看日志") { self.openLogsFolder() },
                AppError.Action("重试", isPrimary: true) {
                    Task { await self.installRuntime(force: true) }
                },
            ])
        }
    }

    // MARK: - 模型

    func refreshModels() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let roots = settings.scanRoots.map { URL(fileURLWithPath: $0) }
        let scanner = self.scanner
        let candidates = await Task.detached(priority: .userInitiated) {
            scanner.scan(roots: roots)
        }.value
        _ = await catalog.syncScanned(candidates: candidates)
        models = await catalog.refreshAvailability()
        applyDefaultResidentModelIfNeeded()
        await refreshServers()
    }

    func addScanRoot(_ url: URL) {
        let path = url.standardizedFileURL.path
        settingsStore.update { settings in
            guard !settings.scanRoots.contains(path) else { return }
            settings.scanRoots.append(path)
        }
        Task { await refreshModels() }
    }

    func removeScanRoot(_ path: String) {
        settingsStore.update { settings in
            settings.scanRoots.removeAll { $0 == path }
        }
        Task { await refreshModels() }
    }

    func importModel(at url: URL) async {
        do {
            _ = try await catalog.importModel(at: url)
            models = await catalog.all()
        } catch {
            report(error, title: "无法导入这个模型", code: "MODEL_IMPORT", actions: [
                AppError.Action("打开模型目录") { self.openAppSupportFolder() },
            ])
        }
    }

    func downloadModel(
        repoID: String,
        progress: @escaping @Sendable (DownloadProgress) -> Void
    ) async throws -> ModelRecord {
        let directory = try await downloader.download(repoID: repoID, progress: progress)
        let record = await catalog.registerDownloaded(at: directory, name: repoID)
        models = await catalog.all()
        // 首次下载完成后直接设为常驻模型，用户不用再手动选一次。
        applyDefaultResidentModelIfNeeded()
        return record
    }

    func removeModel(_ record: ModelRecord) async {
        await serverPool.stop(modelID: record.id, reason: "removed")
        do {
            try await catalog.remove(id: record.id)
        } catch {
            report(error, title: "删除模型失败", code: "MODEL_REMOVE", actions: [
                AppError.Action("在 Finder 中显示") { self.revealInFinder(record) },
            ])
        }
        if settings.residentModelID == record.id {
            setResidentModelID(nil)
        }
        models = await catalog.all()
        await refreshServers()
    }

    func setResidentModelID(_ id: String?) {
        let previous = settings.residentModelID
        settingsStore.update { $0.residentModelID = id }
        Task { @MainActor in
            if let previous, previous != id {
                await serverPool.stop(modelID: previous, reason: "resident-changed")
            }
            if let id, let record = models.first(where: { $0.id == id }) {
                await startServer(for: record)
            }
            await refreshServers()
        }
    }

    func ensureResidentModel() async {
        guard let record = residentModel else { return }
        await startServer(for: record)
    }

    var residentModel: ModelRecord? {
        guard let id = settings.residentModelID else { return nil }
        return models.first { $0.id == id }
    }

    private func applyDefaultResidentModelIfNeeded() {
        guard settings.residentModelID == nil else { return }
        let candidates = models.filter(\.isAvailable)
        guard !candidates.isEmpty else { return }
        if let preferred = candidates.first(where: { $0.name.lowercased().contains("qwen3.5-4b") }) {
            settingsStore.update { $0.residentModelID = preferred.id }
        }
    }

    private func restoreResidentModel() async {
        guard let record = residentModel, record.isAvailable else { return }
        await startServer(for: record)
    }

    // MARK: - 服务进程

    func runtimeRef(for record: ModelRecord) -> ModelRef {
        ModelRef(id: record.id, name: record.name, directory: record.directoryURL)
    }

    func launchConfig(for record: ModelRecord) -> ServerLaunchConfig {
        let service = settings.service(for: record.id)
        return ServerLaunchConfig(
            isResident: record.id == settings.residentModelID,
            idleUnloadMinutes: service.idleUnloadMinutes,
            options: ServerOptions(
                kvCacheBits: service.kvCacheBits,
                maxKVCacheLength: service.maxKVCacheLength
            )
        )
    }

    func startServer(for record: ModelRecord) async {
        guard record.isAvailable else { return }
        do {
            _ = try await serverPool.ensure(model: runtimeRef(for: record), config: launchConfig(for: record))
        } catch {
            report(error, title: "模型服务启动失败", code: "SERVER_START", actions: [
                AppError.Action("查看日志") { self.openLog(for: record) },
                AppError.Action("重试", isPrimary: true) {
                    Task { await self.startServer(for: record) }
                },
            ])
        }
        await refreshServers()
    }

    func stopServer(for record: ModelRecord) async {
        await serverPool.stop(modelID: record.id, reason: "manual")
        await refreshServers()
    }

    func restartServer(for record: ModelRecord) async {
        do {
            _ = try await serverPool.restart(modelID: record.id)
        } catch {
            report(error, title: "模型服务重启失败", code: "SERVER_RESTART", actions: [
                AppError.Action("查看日志") { self.openLog(for: record) },
            ])
        }
        await refreshServers()
    }

    func state(for record: ModelRecord) -> ServerState {
        servers.first { $0.model.id == record.id }?.state ?? .stopped
    }

    func snapshot(for record: ModelRecord) -> ServerSnapshot? {
        servers.first { $0.model.id == record.id }
    }

    private func startStatusLoop() {
        statusTask?.cancel()
        statusTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                await self?.refreshServers()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func refreshServers() async {
        servers = await serverPool.snapshot()
    }

    // MARK: - 设置

    func updateScene(_ scene: SceneID, _ mutate: (inout SceneSettings) -> Void) {
        settingsStore.update { settings in
            var sceneSettings = settings.scene(scene)
            mutate(&sceneSettings)
            settings.setScene(sceneSettings, for: scene)
        }
    }

    func updateGeneral(_ mutate: (inout GeneralSettings) -> Void) {
        settingsStore.update { settings in
            mutate(&settings.general)
        }
    }

    func updateAudioSession(_ mutate: (inout AudioSessionSettings) -> Void) {
        settingsStore.update { settings in
            mutate(&settings.audioSession)
        }
    }

    func updateSubtitle(_ mutate: (inout SubtitleSettings) -> Void) {
        settingsStore.update { settings in
            mutate(&settings.subtitle)
        }
    }

    func updateService(_ modelID: String, _ mutate: (inout ServiceSettings) -> Void) {
        settingsStore.update { settings in
            var service = settings.service(for: modelID)
            mutate(&service)
            settings.setService(service, for: modelID)
        }
    }

    func applyServiceAndRestart(_ record: ModelRecord) async {
        settingsStore.saveNow()
        let state = await serverPool.state(for: record.id)
        guard state.isRunning else { return }
        await restartServer(for: record)
    }

    // MARK: - 辅助

    var hotkeyDisplay: String {
        settings.general.hotkey.displayString
    }

    var statusSummary: String {
        if !runtimeInstalled {
            return "运行时准备中：\(runtimeProgress.message)"
        }
        if let resident = residentModel {
            let state = state(for: resident)
            switch state {
            case .ready: return "常驻模型 \(resident.name) 已就绪"
            case .starting: return "常驻模型 \(resident.name) 加载中…"
            case .failed: return "常驻模型加载失败"
            default: return "常驻模型未运行"
            }
        }
        return models.isEmpty ? "尚未添加模型" : "尚未设置常驻模型"
    }

    func openLogsFolder() {
        try? FileManager.default.createDirectory(at: paths.logsDirectory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(paths.logsDirectory)
    }

    func openAppSupportFolder() {
        try? paths.prepare()
        NSWorkspace.shared.open(paths.appSupportDirectory)
    }

    func openLog(for record: ModelRecord) {
        let url = paths.logURL(forModel: record.name)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
        } else {
            openLogsFolder()
        }
    }

    func revealInFinder(_ record: ModelRecord) {
        NSWorkspace.shared.activateFileViewerSelecting([record.directoryURL])
    }

    func translateClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            reportMessage(
                "剪贴板里没有可翻译的文本。先复制一段文字，或手动输入。",
                title: "没有可翻译的内容",
                code: "CLIPBOARD_EMPTY",
                actions: [
                    AppError.Action("手动输入", isPrimary: true) {
                        self.coordinator.openManualPanel()
                    },
                ]
            )
            return
        }
        coordinator.translate(text: text)
    }

    func showMainWindow(_ tab: MainTab? = nil, meetingID: String? = nil) {
        if let tab { mainTab = tab }
        if let meetingID { focusMeetingID = meetingID }
        MainWindowController.shared.show()
    }

    // MARK: - 错误上报

    func report(
        _ error: Error,
        title: String = "出错了",
        code: String? = nil,
        actions: [AppError.Action] = []
    ) {
        lastError = AppError(title: title, message: error.localizedDescription, code: code, actions: actions)
    }

    func reportMessage(
        _ message: String,
        title: String = "出错了",
        code: String? = nil,
        actions: [AppError.Action] = []
    ) {
        lastError = AppError(title: title, message: message, code: code, actions: actions)
    }

    func clearError() {
        lastError = nil
    }

    func markMeetingsSeen() {
        hasUnseenMeetings = false
    }
}
