import SwiftUI

/// 结构化错误：标题、说明、可选错误码与若干恢复动作。
/// 目标是让每种失败都能告诉用户「发生了什么、数据安不安全、下一步点哪里」。
struct AppError: Identifiable, Equatable {
    struct Action: Identifiable {
        let id = UUID()
        let title: String
        let isPrimary: Bool
        let handler: () -> Void

        init(_ title: String, isPrimary: Bool = false, handler: @escaping () -> Void) {
            self.title = title
            self.isPrimary = isPrimary
            self.handler = handler
        }
    }

    let id = UUID()
    let title: String
    let message: String
    let code: String?
    let actions: [Action]

    init(title: String, message: String, code: String? = nil, actions: [Action] = []) {
        self.title = title
        self.message = message
        self.code = code
        self.actions = actions
    }

    static func == (lhs: AppError, rhs: AppError) -> Bool {
        lhs.id == rhs.id
    }
}

/// 主窗口顶部的错误条：比 alert 更适合承载两个恢复动作和错误码。
struct ProblemBanner: View {
    let error: AppError
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18))
                .foregroundStyle(Color.danger)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(error.title)
                    .font(.system(size: 13, weight: .semibold))
                Text(error.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                if let code = error.code {
                    Text(code)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 8)

            ForEach(error.actions) { action in
                if action.isPrimary {
                    Button(action.title) { action.handler() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                } else {
                    Button(action.title) { action.handler() }
                        .controlSize(.small)
                }
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
            .accessibilityLabel("关闭错误提示")
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.danger.opacity(0.25))
        )
        .shadow(color: .black.opacity(0.16), radius: 12, y: 5)
    }
}
