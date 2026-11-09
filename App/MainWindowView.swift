import SwiftUI

enum MainTab: String, Hashable, CaseIterable, Identifiable {
    case home
    case meetings
    case models
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .home: return "首页"
        case .meetings: return "会议"
        case .models: return "模型"
        case .settings: return "设置"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house"
        case .meetings: return "waveform"
        case .models: return "square.stack.3d.up"
        case .settings: return "gearshape"
        }
    }
}

struct MainWindowView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                sidebarBrand
                List(MainTab.allCases, selection: tabBinding) { tab in
                    HStack(spacing: 6) {
                        Label(tab.title, systemImage: tab.systemImage)
                        if tab == .meetings, environment.hasUnseenMeetings {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 5, height: 5)
                                .accessibilityLabel("有新的会议记录")
                        }
                        Spacer(minLength: 0)
                    }
                    .tag(tab)
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
            .safeAreaInset(edge: .bottom) {
                SidebarStatusFooter()
            }
        } detail: {
            detail
                .navigationTitle(environment.mainTab.title)
        }
        .frame(minWidth: 940, minHeight: 600)
        .onChange(of: environment.mainTab) { _, tab in
            if tab == .meetings {
                environment.markMeetingsSeen()
            }
        }
        .overlay(alignment: .top) {
            if let error = environment.lastError {
                ProblemBanner(error: error, onDismiss: environment.clearError)
                    .padding(.top, 12)
                    .padding(.horizontal, 20)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: environment.lastError)
        .sheet(isPresented: $environment.isOnboardingPresented) {
            OnboardingView()
                .environmentObject(environment)
        }
        .overlay(alignment: .bottom) {
            if let toast = environment.toast {
                ToastBanner(
                    toast: toast,
                    onAction: environment.performToastAction,
                    onDismiss: environment.dismissToast
                )
                .fixedSize(horizontal: true, vertical: false)
                .padding(.bottom, 20)
                .padding(.horizontal, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: environment.toast)
    }

    @ViewBuilder
    private var detail: some View {
        switch environment.mainTab {
        case .home: HomeView()
        case .meetings: MeetingsView()
        case .models: ModelsView()
        case .settings: AppSettingsView()
        }
    }

    private var sidebarBrand: some View {
        HStack(spacing: 8) {
            Image("BrandIcon")
                .resizable()
                .interpolation(.high)
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
            Text("LingoLens")
                .font(.system(size: 13, weight: .semibold))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
    }

    private var tabBinding: Binding<MainTab?> {
        Binding(
            get: { environment.mainTab },
            set: { if let tab = $0 { environment.mainTab = tab } }
        )
    }
}

/// 侧边栏底部：常驻模型与音频会话状态。
private struct SidebarStatusFooter: View {
    @EnvironmentObject private var environment: AppEnvironment
    @ObservedObject private var updater = AppUpdater.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if environment.audioSession.state == .running {
                HStack(spacing: 6) {
                    Circle().fill(Color.danger).frame(width: 7, height: 7)
                    Text(environment.audioSession.isRecordingMeeting ? "正在记录会议" : "音频会话运行中")
                }
            }
            HStack(spacing: 6) {
                Circle().fill(environment.residentStatusColor).frame(width: 7, height: 7)
                Text(environment.statusSummary)
                    .lineLimit(2)
            }
            Text("完全本地运行")
                .foregroundStyle(.tertiary)
            HStack(spacing: 6) {
                Text(AppUpdater.versionText)
                    .monospacedDigit()
                if let version = updater.availableUpdateVersion {
                    // 有新版本：换成带箭头的强调色按钮，和菜单栏面板保持一致。
                    Button {
                        updater.checkForUpdates()
                    } label: {
                        Label("有新版本 \(version)", systemImage: "arrow.down.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(!updater.canCheckForUpdates)
                    .help("点击更新到 \(version)")
                    .accessibilityLabel("有新版本 \(version)，点击更新")
                } else {
                    Button("检查更新") { updater.checkForUpdates() }
                        .buttonStyle(.link)
                        .disabled(!updater.canCheckForUpdates)
                }
            }
            .foregroundStyle(.tertiary)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }
}

extension AppEnvironment {
    /// 常驻模型状态对应的指示色，侧边栏、首页、菜单栏共用。
    var residentStatusColor: Color {
        guard runtimeInstalled, let resident = residentModel else { return Color.warning }
        switch state(for: resident) {
        case .ready: return Color.success
        case .starting, .stopping: return Color.warning
        case .failed: return Color.danger
        case .stopped: return .secondary
        }
    }
}
