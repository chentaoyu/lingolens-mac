import SwiftUI

/// 轻量操作回执。会话结束、导出完成这类「刚做完一件事」的提示，
/// 需要在主窗口与菜单栏面板里都能看到，因此做成一个共享的小模型。
struct AppToast: Identifiable, Equatable {
    enum Action: Equatable {
        case openMeeting(String)
    }

    let id = UUID()
    let title: String
    let subtitle: String
    var systemImage = "checkmark.circle.fill"
    var actionTitle: String?
    var action: Action?

    static func == (lhs: AppToast, rhs: AppToast) -> Bool {
        lhs.id == rhs.id
    }
}

struct ToastBanner: View {
    let toast: AppToast
    let onAction: (AppToast.Action) -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.systemImage)
                .font(.system(size: 17))
                .foregroundStyle(Color.success)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(toast.title)
                    .font(.system(size: 13, weight: .semibold))
                Text(toast.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: 340, alignment: .leading)

            Spacer(minLength: 8)

            if let actionTitle = toast.actionTitle, let action = toast.action {
                Button(actionTitle) { onAction(action) }
                    .controlSize(.small)
            }

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("关闭提示")
            .accessibilityLabel("关闭提示")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
        .shadow(color: .black.opacity(0.16), radius: 14, y: 6)
    }
}
