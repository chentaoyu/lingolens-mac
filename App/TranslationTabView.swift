import AppKit
import SelectionTranslate
import Settings
import SwiftUI

struct TranslationTabView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                actions
                status
                tips
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("划词翻译")
                .font(.system(size: 22, weight: .semibold))
            Text("在任意应用选中文字后按 \(environment.hotkeyDisplay)，浮窗会显示译文；也可以直接使用下面的按钮。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button("读取选中文字并翻译") {
                environment.coordinator.trigger()
            }
            .keyboardShortcut("d", modifiers: .option)

            Button("翻译剪贴板内容") {
                environment.translateClipboard()
            }

            Button("打开空白翻译浮窗") {
                environment.coordinator.openManualPanel()
            }

            Spacer()

            Button("辅助功能设置") {
                AccessibilityPermission.openSystemSettings()
            }
        }
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: 8) {
            statusRow(
                "快捷键",
                environment.coordinator.isHotkeyRegistered
                    ? environment.hotkeyDisplay
                    : "\(environment.hotkeyDisplay)（注册失败，可能被其他应用占用）"
            )
            statusRow("目标语言", TranslationPrompt.languageName(environment.settings.general.targetLanguage))
            statusRow("常驻模型", environment.residentModel?.name ?? "未设置")
            statusRow("辅助功能权限", AccessibilityPermission.isTrusted ? "已授权" : "未授权（将退化为模拟 ⌘C）")
            statusRow("翻译场景模型", environment.settings.scene(.selectionTranslation).useResidentModel ? "使用常驻模型" : "指定独立模型")
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.06))
        )
    }

    private var tips: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("看不到翻译浮窗？")
                .font(.system(size: 12, weight: .semibold))
            VStack(alignment: .leading, spacing: 3) {
                Text("• 菜单栏图标（右上角气泡）→「划词翻译」也能触发。")
                Text("• 若系统未授权辅助功能，会自动尝试模拟 ⌘C；仍失败则打开空白浮窗手动输入。")
                Text("• 系统菜单栏拥挤时图标可能被收纳，可在“系统设置 → 控制中心”里把 LingoLens 设为始终显示。")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func statusRow(_ title: String, _ value: String) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
            Text(value)
                .font(.system(size: 12))
            Spacer()
        }
    }
}
