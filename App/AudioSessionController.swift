import AudioCapture
import AVFoundation
import Foundation
import LiveSubtitle
import Meetings
import ModelRuntime
import Settings
import Transcriber

/// 音频会话：采集 → 双路转写 → 字幕/翻译 → 会议记录。
@MainActor
final class AudioSessionController: ObservableObject {
    enum State: Equatable {
        case idle
        case starting
        case running
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var statusText = "未开始"
    @Published private(set) var isRecordingMeeting = false
    @Published private(set) var activeLanguages: [AudioChannel: String] = [:]
    @Published private(set) var startedAt: Date?
    /// 两路音频的当前电平（0…1），菜单栏用来显示「有没有采到声音」。
    @Published private(set) var levels: [AudioChannel: Float] = [:]

    /// 会话结束后通知界面刷新会议列表。
    var onSessionFinished: (() -> Void)?

    private let settingsStore: SettingsStore
    private let subtitleStore: SubtitleStore
    private let translation: SubtitleTranslationController
    private let meetingStore: MeetingStore
    private let paths: RuntimePaths
    private let capture = AudioCaptureController()

    private var sessions: [AudioChannel: SpeechTranscriptionSession] = [:]
    private var captureTask: Task<Void, Never>?
    private var eventTasks: [AudioChannel: Task<Void, Never>] = [:]
    private var currentMeeting: MeetingMeta?
    /// 录音落盘：每路一个 m4a，会议目录下 `audio-<channel>.m4a`。
    private var recorders: [AudioChannel: ChannelAudioRecorder] = [:]
    /// Whisper 边车进程，仅在选择 Whisper 引擎时存在。
    private var whisperSessions: [AudioChannel: WhisperTranscriber] = [:]

    /// 缓冲区间累积的峰值，由电平循环按固定帧率取走并平滑衰减。
    private var levelPeak: [AudioChannel: Float] = [:]
    private var levelTask: Task<Void, Never>?

    init(
        settingsStore: SettingsStore,
        subtitleStore: SubtitleStore,
        translation: SubtitleTranslationController,
        meetingStore: MeetingStore,
        paths: RuntimePaths
    ) {
        self.settingsStore = settingsStore
        self.subtitleStore = subtitleStore
        self.translation = translation
        self.meetingStore = meetingStore
        self.paths = paths

        translation.onTranslation = { [weak self] id, text in
            self?.applyTranslation(lineID: id, text: text)
        }
    }

    func toggle() async {
        if state == .running || state == .starting {
            await stop()
        } else {
            await start()
        }
    }

    func start() async {
        guard state != .running, state != .starting else { return }
        let config = settingsStore.settings.audioSession

        var languages: [AudioChannel: [String]] = [:]
        var languageLabels: [AudioChannel: String] = [:]
        if config.captureSystemAudio {
            languages[.other] = AudioLanguageSettings.locales(for: config.otherLanguage)
            languageLabels[.other] = config.otherLanguage
        }
        if config.captureMicrophone {
            languages[.me] = AudioLanguageSettings.locales(for: config.meLanguage)
            languageLabels[.me] = config.meLanguage
        }
        guard !languages.isEmpty else {
            state = .failed("请至少选择一路音频来源")
            statusText = "未选择音频来源"
            return
        }

        state = .starting
        statusText = "准备语音模型…"

        // 未决定时先弹出麦克风授权，避免直接以“权限被拒绝”失败。
        if config.captureMicrophone, MicrophoneCapture.authorizationStatus == .notDetermined {
            statusText = "请求麦克风权限…"
            _ = await MicrophoneCapture.requestAccess()
        }

        do {
            if config.recordMeetings {
                let meta = try await meetingStore.create(title: nil, languages: languageLabels)
                currentMeeting = meta
                isRecordingMeeting = true
                if config.recordAudio {
                    await startRecorders(meetingID: meta.id, channels: Array(languages.keys))
                }
            }

            let useWhisper = settingsStore.settings.speech.engine == .whisper
                && SpeechModelInstaller(paths: paths).isInstalled
            if settingsStore.settings.speech.engine == .whisper, !useWhisper {
                // 选了 Whisper 但模型还没装：退回系统识别，别让用户没有字幕。
                statusText = "Whisper 模型未下载，暂用系统识别"
                AppLog.write("[speech] whisper 模型未安装，回退系统识别")
            }

            for (channel, identifiers) in languages {
                if useWhisper {
                    try await startWhisper(channel: channel, identifiers: identifiers)
                    continue
                }
                statusText = "准备\(channel.displayName)语音模型…"
                let session = SpeechTranscriptionSession(channel: channel)
                let events = try await session.start(localeIdentifiers: identifiers)
                sessions[channel] = session
                eventTasks[channel] = Task { @MainActor [weak self] in
                    for await event in events {
                        self?.handle(event)
                    }
                }
            }

            activeLanguages = languageLabels
            statusText = "等待音频…"
            let stream = try capture.start(
                options: AudioCaptureOptions(
                    captureSystemAudio: config.captureSystemAudio,
                    captureMicrophone: config.captureMicrophone
                )
            )

            captureTask = Task { @MainActor [weak self] in
                for await tagged in stream {
                    guard let self else { continue }
                    let level = AudioBufferTools.level(of: tagged.buffer)
                    self.levelPeak[tagged.channel] = max(self.levelPeak[tagged.channel] ?? 0, level)
                    // 录音与转写各拿一份：录音内部转成 16k 单声道，不阻塞采集。
                    self.recorders[tagged.channel]?.append(tagged.buffer)
                    guard let session = self.sessions[tagged.channel] else { continue }
                    await session.append(tagged.buffer)
                }
            }

            state = .running
            startedAt = Date()
            startLevelLoop()
            if capture.warnings.isEmpty {
                statusText = "字幕运行中"
            } else {
                statusText = "部分来源不可用：\(capture.warnings.joined(separator: "；"))"
            }
        } catch {
            await stop()
            state = .failed(error.localizedDescription)
            statusText = error.localizedDescription
        }
    }

    /// 结束时返回刚才落盘的会议（没有记录会议时为 nil），供界面给出「会议已保存」回执。
    @discardableResult
    func stop() async -> MeetingMeta? {
        captureTask?.cancel()
        captureTask = nil
        capture.stop()
        stopLevelLoop()

        // 先让每路会话收尾，事件消费者仍在运行，避免丢掉最后的 final 结果。
        for session in sessions.values {
            await session.finish()
        }
        sessions.removeAll()

        // 边车要等最后一段转写完，放在取消事件消费者之前。
        for transcriber in whisperSessions.values {
            await transcriber.finish()
        }
        whisperSessions.removeAll()

        for task in eventTasks.values {
            task.cancel()
        }
        eventTasks.removeAll()

        let finishedMeeting = currentMeeting
        if let meeting = currentMeeting {
            await finishRecorders(meetingID: meeting.id)
            try? await meetingStore.finish(id: meeting.id)
        }
        currentMeeting = nil
        isRecordingMeeting = false
        activeLanguages = [:]
        startedAt = nil
        state = .idle
        statusText = "已停止"
        onSessionFinished?()
        return finishedMeeting
    }

    // MARK: - Whisper

    /// 一路 Whisper 边车。字幕按句出现，因此在音频会话里也按句上报。
    private func startWhisper(channel: AudioChannel, identifiers: [String]) async throws {
        statusText = "加载 Whisper 模型（\(channel.displayName)）…"
        let settings = settingsStore.settings.speech
        let installer = SpeechModelInstaller(paths: paths)
        let script = try Self.sttScriptURL()

        let transcriber = WhisperTranscriber(
            modelDirectory: installer.directory,
            pythonExecutable: paths.pythonExecutable,
            scriptURL: script,
            language: Self.whisperLanguage(for: identifiers),
            hotwords: settings.hotwordList
        )
        let events = try await transcriber.start()
        whisperSessions[channel] = transcriber

        eventTasks[channel] = Task { @MainActor [weak self] in
            for await event in events {
                guard let self else { return }
                switch event {
                case let .final(segment):
                    self.handle(TranscriptionEvent(
                        channel: channel,
                        text: segment.text,
                        isFinal: true,
                        language: identifiers.first
                    ))
                case let .failure(message):
                    AppLog.write("[speech] whisper 失败：\(message)")
                case .ready:
                    break
                }
            }
        }
    }

    /// 边车脚本路径：优先 Bundle，开发期回退到仓库里的资源目录。
    private static func sttScriptURL() throws -> URL {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("stt/lingolens_stt.py"),
           FileManager.default.fileExists(atPath: bundled.path) {
            return bundled
        }
        throw TranscriptionError.assetInstallationFailed("找不到语音转写脚本 lingolens_stt.py")
    }

    /// Whisper 只接受单种语言代码；设置里的 zh-Hans / en 映射过去。
    private static func whisperLanguage(for identifiers: [String]) -> String {
        for identifier in identifiers where identifier.hasPrefix("zh") {
            return "zh"
        }
        return identifiers.first.map { $0.hasPrefix("en") ? "en" : $0 } ?? "zh"
    }

    // MARK: - 录音落盘

    /// 为每路建一个 m4a。失败只记日志，不影响转写本身。
    private func startRecorders(meetingID: String, channels: [AudioChannel]) async {
        recorders.removeAll()
        for channel in channels {
            let url = await meetingStore.audioFileURL(id: meetingID, channel: channel)
            do {
                recorders[channel] = try ChannelAudioRecorder(url: url)
            } catch {
                AppLog.write("[audio] 无法创建录音文件 \(channel.rawValue): \(error.localizedDescription)")
            }
        }
    }

    /// 收尾：等所有音频写完再登记到 meta，保证记录与文件一致。
    private func finishRecorders(meetingID: String) async {
        guard !recorders.isEmpty else { return }
        var files: [AudioChannel: URL] = [:]
        for (channel, recorder) in recorders {
            recorder.finish()
            // 没有任何音频（例如那一路没有权限）就不登记空文件。
            if recorder.writtenFrames > 0 {
                files[channel] = recorder.url
            } else {
                try? FileManager.default.removeItem(at: recorder.url)
            }
            AppLog.write(
                "[audio] \(channel.rawValue) 录音结束 时长=\(String(format: "%.1f", recorder.duration))s "
                    + "写入失败=\(recorder.failureCount)"
            )
        }
        recorders.removeAll()
        if !files.isEmpty {
            try? await meetingStore.setAudioFiles(id: meetingID, files: files)
        }
    }

    // MARK: - 电平

    /// 以约 15 Hz 更新电平：上升立刻跟随，回落按系数衰减，避免条状指示抖动。
    private func startLevelLoop() {
        levelTask?.cancel()
        levelTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(66))
                guard let self else { return }
                var next = self.levels
                for channel in AudioChannel.allCases {
                    let peak = self.levelPeak[channel] ?? 0
                    let previous = self.levels[channel] ?? 0
                    next[channel] = peak > previous ? peak : max(0, previous * 0.88)
                }
                self.levelPeak = [:]
                if next != self.levels {
                    self.levels = next
                }
            }
        }
    }

    private func stopLevelLoop() {
        levelTask?.cancel()
        levelTask = nil
        levelPeak = [:]
        if !levels.isEmpty {
            levels = [:]
        }
    }

    private func handle(_ event: TranscriptionEvent) {
        let lineID = subtitleStore.apply(event)
        guard event.isFinal, let lineID else { return }

        guard isRecordingMeeting, let meeting = currentMeeting else {
            translation.enqueue(
                id: lineID,
                channel: event.channel,
                text: event.text,
                sourceLanguage: event.language
            )
            return
        }

        let entry = TranscriptEntry(
            id: lineID,
            time: event.timestamp,
            speaker: event.channel,
            text: event.text
        )
        Task {
            // 先落盘再翻译，保证翻译回写时条目已存在。
            try? await meetingStore.append(entry, to: meeting.id)
            translation.enqueue(
                id: lineID,
                channel: event.channel,
                text: event.text,
                sourceLanguage: event.language
            )
        }
    }

    private func applyTranslation(lineID: UUID, text: String) {
        guard isRecordingMeeting, let meeting = currentMeeting else { return }
        Task {
            try? await meetingStore.updateTranslation(
                meetingID: meeting.id,
                entryID: lineID,
                translation: text
            )
        }
    }
}
