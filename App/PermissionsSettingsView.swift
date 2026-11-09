import AVFoundation
import AppKit
import SelectionTranslate
import SwiftUI

struct PermissionsSettingsView: View {
    @State private var accessibilityState: AccessibilityTrustState = .granted
    @State private var microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)

    var body: some View {
        Group {
            permissionRow(
                title: "辅助功能",
                detail: accessibilityDetail,
                granted: accessibilityState.isUsable,
                requestTitle: "请求授权",
                request: {
                    AccessibilityPermission.request()
                    refresh()
                },
                openSettings: {
                    open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
                }
            )
            if accessibilityState == .needsRestart {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .foregroundStyle(Color.warning)
                    Text("系统里已经授权，但本次运行还读不到。macOS 把授权结果缓存在进程里，重启一次即可生效。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("重启 LingoLens") { AccessibilityPermission.relaunch() }
                        .controlSize(.small)
                }
            }

            permissionRow(
                title: "麦克风",
                detail: "采集“我”这一路语音；拒绝后只保留系统音频这一路（v2 起使用）。",
                granted: microphoneStatus == .authorized,
                requestTitle: microphoneStatus == .notDetermined ? "请求授权" : "重新请求",
                request: {
                    AVCaptureDevice.requestAccess(for: .audio) { _ in }
                },
                openSettings: {
                    open("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
                }
            )

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "speaker.wave.2.badge.gearshape")
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text("系统音频录制（对方）")
                        .font(.system(size: 12, weight: .medium))
                    Text("首次开始音频会话时，系统会请求“系统音频录制”权限；拒绝后可改用麦克风，或到系统设置中开启。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("刷新状态") { refresh() }
                    .controlSize(.small)
                Button("打开系统设置") {
                    open("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
                }
                .controlSize(.small)
            }
        }
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
    }

    private func permissionRow(
        title: String,
        detail: String,
        granted: Bool,
        requestTitle: String,
        request: @escaping () -> Void,
        openSettings: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(granted ? Color.success : Color.warning)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            if !granted {
                Button(requestTitle, action: request)
                    .controlSize(.small)
            }
            Button("打开系统设置", action: openSettings)
                .controlSize(.small)
        }
    }

    private var accessibilityDetail: String {
        switch accessibilityState {
        case .granted:
            return "读取其他应用中选中的文本。"
        case .needsRestart:
            return "系统设置里已勾选，但当前进程还没生效，需要重启应用。"
        case .denied:
            return "读取其他应用中选中的文本。未授权时退化为模拟 ⌘C，仍失败则打开空浮窗手动输入。"
        }
    }

    private func refresh() {
        microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        // 判定可能要起子进程复查，别让它卡住设置界面。
        Task.detached(priority: .utility) {
            let state = AccessibilityPermission.resolvedState()
            await MainActor.run { accessibilityState = state }
        }
    }

    private func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}