import AudioCapture
import AVFoundation
import Foundation
import LiveSubtitle
import Meetings
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

    /// 会话结束后通知界面刷新会议列表。
    var onSessionFinished: (() -> Void)?

    private let settingsStore: SettingsStore
    private let subtitleStore: SubtitleStore
    private let translation: SubtitleTranslationController
    private let meetingStore: MeetingStore
    private let capture = AudioCaptureController()

    private var sessions: [AudioChannel: SpeechTranscriptionSession] = [:]
    private var captureTask: Task<Void, Never>?
    private var eventTasks: [AudioChannel: Task<Void, Never>] = [:]
    private var currentMeeting: MeetingMeta?

    init(
        settingsStore: SettingsStore,
        subtitleStore: SubtitleStore,
        translation: SubtitleTranslationController,
        meetingStore: MeetingStore
    ) {
        self.settingsStore = settingsStore
        self.subtitleStore = subtitleStore
        self.translation = translation
        self.meetingStore = meetingStore

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

        var languages: [AudioChannel: String] = [:]
        if config.captureSystemAudio { languages[.other] = config.otherLanguage }
        if config.captureMicrophone { languages[.me] = config.meLanguage }
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
                let meta = try await meetingStore.create(title: nil, languages: languages)
                currentMeeting = meta
                isRecordingMeeting = true
            }

            for (channel, locale) in languages {
                statusText = "准备\(channel.displayName)语音模型…"
                let session = SpeechTranscriptionSession(channel: channel)
                let events = try await session.start(localeIdentifier: locale)
                sessions[channel] = session
                eventTasks[channel] = Task { @MainActor [weak self] in
                    for await event in events {
                        self?.handle(event)
                    }
                }
            }

            activeLanguages = languages
            statusText = "等待音频…"
            let stream = try capture.start(
                options: AudioCaptureOptions(
                    captureSystemAudio: config.captureSystemAudio,
                    captureMicrophone: config.captureMicrophone
                )
            )

            captureTask = Task { @MainActor [weak self] in
                for await tagged in stream {
                    guard let self, let session = self.sessions[tagged.channel] else { continue }
                    await session.append(tagged.buffer)
                }
            }

            state = .running
            startedAt = Date()
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

    func stop() async {
        captureTask?.cancel()
        captureTask = nil
        capture.stop()

        // 先让每路会话收尾，事件消费者仍在运行，避免丢掉最后的 final 结果。
        for session in sessions.values {
            await session.finish()
        }
        sessions.removeAll()

        for task in eventTasks.values {
            task.cancel()
        }
        eventTasks.removeAll()

        if let meeting = currentMeeting {
            try? await meetingStore.finish(id: meeting.id)
        }
        currentMeeting = nil
        isRecordingMeeting = false
        activeLanguages = [:]
        startedAt = nil
        state = .idle
        statusText = "已停止"
        onSessionFinished?()
    }

    private func handle(_ event: TranscriptionEvent) {
        let lineID = subtitleStore.apply(event)
        guard event.isFinal, let lineID else { return }

        guard isRecordingMeeting, let meeting = currentMeeting else {
            translation.enqueue(id: lineID, channel: event.channel, text: event.text)
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
            translation.enqueue(id: lineID, channel: event.channel, text: event.text)
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
