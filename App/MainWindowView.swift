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

    var body: some View {
        NavigationSplitView {
            List(MainTab.allCases, selection: tabBinding) { tab in
                Label(tab.title, systemImage: tab.systemImage)
                    .tag(tab)
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
        .alert(
            "出错了",
            isPresented: Binding(
                get: { environment.lastError != nil },
                set: { if !$0 { environment.clearError() } }
            ),
            presenting: environment.lastError
        ) { _ in
            Button("好") { environment.clearError() }
        } message: { message in
            Text(message)
        }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if environment.audioSession.state == .running {
                HStack(spacing: 6) {
                    Circle().fill(.red).frame(width: 7, height: 7)
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
        guard runtimeInstalled, let resident = residentModel else { return .orange }
        switch state(for: resident) {
        case .ready: return .green
        case .starting, .stopping: return .orange
        case .failed: return .red
        case .stopped: return .secondary
        }
    }
}
