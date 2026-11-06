import Meetings
import ModelLibrary
import ModelRuntime
import SelectionTranslate
import SwiftUI

/// 首页：状态总览、待处理问题、快捷操作与最近会议。
struct HomeView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var recentMeetings: [MeetingSummary] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                issues
                HStack(alignment: .top, spacing: 14) {
                    residentModelCard
                    runtimeCard
                }
                quickActions
                recentSection
            }
            .padding(24)
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .task(id: environment.meetingsRevision) {
            recentMeetings = Array(await environment.loadMeetings().prefix(3))
        }
    }

    // MARK: - 头部

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("LingoLens")
                    .font(.system(size: 24, weight: .semibold))
                Text("翻译、实时字幕与会议纪要，全部在这台 Mac 上完成。")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            SessionButton()
                .controlSize(.large)
        }
    }

    // MARK: - 待处理问题

    @ViewBuilder
    private var issues: some View {
        if environment.runtimeProgress.phase == .failed {
            IssueBanner(
                title: "运行时安装失败",
                message: environment.runtimeProgress.message,
                tint: .red
            ) {
                Button("查看日志") { environment.openLogsFolder() }
                Button("重试") { Task { await environment.installRuntime(force: true) } }
                    .buttonStyle(.borderedProminent)
            }
        }
        if let resident = environment.residentModel, case let .failed(message) = environment.state(for: resident) {
            IssueBanner(title: "常驻模型启动失败", message: message, tint: .red) {
                Button("查看日志") { environment.openLog(for: resident) }
                Button("重试") { Task { await environment.startServer(for: resident) } }
                    .buttonStyle(.borderedProminent)
            }
        }
        if environment.residentModel == nil {
            IssueBanner(
                title: environment.models.isEmpty ? "还没有模型" : "尚未设置常驻模型",
                message: "划词翻译、字幕翻译和会议纪要都需要一个本地模型。",
                tint: .orange
            ) {
                Button("去模型页") { environment.mainTab = .models }
                    .buttonStyle(.borderedProminent)
            }
        }
        if !AccessibilityPermission.isTrusted {
            IssueBanner(
                title: "未授予辅助功能权限",
                message: "划词翻译会退化为模拟 ⌘C 读取选中文字，部分应用可能取不到。",
                tint: .orange
            ) {
                Button("去授权") { AccessibilityPermission.openSystemSettings() }
            }
        }
        if !environment.coordinator.isHotkeyRegistered {
            IssueBanner(
                title: "快捷键 \(environment.hotkeyDisplay) 注册失败",
                message: "可能被其他应用占用，请在设置中换一个组合键。",
                tint: .orange
            ) {
                Button("去设置") { environment.mainTab = .settings }
            }
        }
    }

    // MARK: - 状态卡片

    private var residentModelCard: some View {
        StatusCard(title: "常驻模型") {
            if let resident = environment.residentModel {
                HStack {
                    Text(resident.name)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    Spacer()
                    ServerStateBadge(state: environment.state(for: resident))
                }
                if let info = resident.info {
                    Text(info.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    MemoryMeter(bytes: info.estimatedMemoryBytes)
                }
            } else {
                Text("未设置")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Button("管理模型") { environment.mainTab = .models }
        }
    }

    private var runtimeCard: some View {
        StatusCard(title: "本地运行时") {
            HStack {
                Text("mlx-vlm")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(environment.runtimeInstalled ? "已就绪" : environment.runtimeProgress.phase == .failed ? "失败" : "准备中")
                    .font(.caption)
                    .foregroundStyle(environment.runtimeInstalled ? .green : .orange)
            }
            Text(environment.runtimeProgress.message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if environment.isInstallingRuntime {
                if let fraction = environment.runtimeProgress.fraction {
                    ProgressView(value: fraction)
                } else {
                    ProgressView().progressViewStyle(.linear)
                }
            }
            Text("运行中的模型服务：\(environment.servers.filter { $0.state.isRunning }.count) 个")
                .font(.caption)
                .foregroundStyle(.secondary)
        } footer: {
            Button("打开日志文件夹") { environment.openLogsFolder() }
        }
    }

    // MARK: - 快捷操作

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("快捷操作").font(.headline)
            HStack(spacing: 12) {
                QuickActionTile(
                    title: "划词翻译",
                    subtitle: "在任意应用选中文字后按 \(environment.hotkeyDisplay)",
                    systemImage: "character.bubble"
                ) {
                    environment.coordinator.openManualPanel()
                }
                QuickActionTile(
                    title: "翻译剪贴板",
                    subtitle: "立即翻译已复制的内容",
                    systemImage: "doc.on.clipboard"
                ) {
                    environment.translateClipboard()
                }
                QuickActionTile(
                    title: "字幕浮窗",
                    subtitle: environment.subtitlePanel.isVisible ? "点击隐藏" : "点击显示",
                    systemImage: "captions.bubble"
                ) {
                    environment.subtitlePanel.toggleVisibility()
                }
            }
        }
    }

    // MARK: - 最近会议

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("最近会议").font(.headline)
                Spacer()
                Button("查看全部") { environment.mainTab = .meetings }
                    .buttonStyle(.link)
            }
            if recentMeetings.isEmpty {
                Text("还没有会议记录。开始音频会话时打开「记录会议」，结束后会出现在这里。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(recentMeetings) { meeting in
                        RecentMeetingRow(meeting: meeting) {
                            environment.focusMeetingID = meeting.id
                            environment.mainTab = .meetings
                        }
                        if meeting.id != recentMeetings.last?.id {
                            Divider()
                        }
                    }
                }
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }
}

// MARK: - 组件

/// 开始/停止音频会话；运行时显示计时。首页与菜单栏共用。
struct SessionButton: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        let session = environment.audioSession
        Button {
            Task {
                if session.state == .running || session.state == .starting {
                    await environment.stopAudioSession()
                } else {
                    await environment.startAudioSession()
                }
            }
        } label: {
            switch session.state {
            case .running:
                Label {
                    SessionTimer(startedAt: session.startedAt)
                } icon: {
                    Image(systemName: "stop.fill")
                }
            case .starting:
                Label("启动中…", systemImage: "hourglass")
            default:
                Label("开始音频会话", systemImage: "waveform")
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(session.state == .running ? .red : .accentColor)
    }
}

struct SessionTimer: View {
    let startedAt: Date?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let seconds = Int(context.date.timeIntervalSince(startedAt ?? context.date))
            Text(String(format: "%02d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60))
                .monospacedDigit()
        }
    }
}

private struct IssueBanner<Actions: View>: View {
    let title: String
    let message: String
    let tint: Color
    @ViewBuilder let actions: Actions

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(tint)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            actions
        }
        .padding(12)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(tint.opacity(0.25)))
    }
}

private struct StatusCard<Content: View, Footer: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @ViewBuilder let footer: Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            content
            Spacer(minLength: 0)
            footer
                .buttonStyle(.link)
                .font(.caption)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// 模型预估内存与本机内存的对比条。
private struct MemoryMeter: View {
    let bytes: Int64

    var body: some View {
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        let ratio = min(1, Double(bytes) / total)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("预估内存").foregroundStyle(.secondary)
                Spacer()
                Text("\(formatBytes(UInt64(max(0, bytes)))) / \(formatBytes(UInt64(total)))")
            }
            .font(.caption)
            ProgressView(value: ratio)
                .tint(ratio > 0.7 ? .orange : .accentColor)
        }
    }
}

private struct QuickActionTile: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(.tint)
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 90, alignment: .topLeading)
            .padding(12)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

private struct RecentMeetingRow: View {
    let meeting: MeetingSummary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(meeting.meta.title).font(.system(size: 13, weight: .medium))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(meeting.hasMinutes ? "已有纪要" : "仅转写")
                    .font(.caption)
                    .foregroundStyle(meeting.hasMinutes ? .green : .secondary)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var subtitle: String {
        let start = meeting.meta.startedAt.formatted(date: .abbreviated, time: .shortened)
        guard let end = meeting.meta.endedAt else { return start }
        let minutes = max(1, Int(end.timeIntervalSince(meeting.meta.startedAt) / 60))
        return "\(start) · \(minutes) 分钟"
    }
}
