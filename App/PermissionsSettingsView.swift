import AVFoundation
import AppKit
import SelectionTranslate
import SwiftUI

struct PermissionsSettingsView: View {
    @State private var accessibilityTrusted = AccessibilityPermission.isTrusted
    @State private var microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("权限")
            Text("仅在用到对应功能时申请；拒绝后会退化到可用的替代方式。")
                .font(.caption)
                .foregroundStyle(.secondary)

            permissionRow(
                title: "辅助功能",
                detail: "读取其他应用中选中的文本。未授权时退化为模拟 ⌘C，仍失败则打开空浮窗手动输入。",
                granted: accessibilityTrusted,
                requestTitle: "请求授权",
                request: {
                    AccessibilityPermission.request()
                    refresh()
                },
                openSettings: {
                    open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
                }
            )

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
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.secondary.opacity(0.05))
            )
        }
        .onAppear(perform: refresh)
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
                .foregroundStyle(granted ? Color.green : Color.orange)
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
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.05))
        )
    }

    private func refresh() {
        accessibilityTrusted = AccessibilityPermission.isTrusted
        microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    }

    private func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}