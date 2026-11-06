import AppKit
import ModelLibrary
import SwiftUI
import UniformTypeIdentifiers

/// 首次启动引导（原型 B 帧）：欢迎 → 运行环境 → 选择模型 → 授权 → 试一试。
/// 每一步都复用应用里已有的状态与操作，不引入第二套逻辑。
struct OnboardingView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    @State private var step = 0
    @State private var showDownload = false
    @State private var isImporting = false

    private var steps: [(label: String, title: String, summary: String)] {
        [
            ("欢迎", "欢迎使用 LingoLens", "翻译、实时字幕和会议纪要，全部在这台 Mac 上完成。数据不会离开设备。"),
            ("运行环境", "准备本地运行环境", "首次启动会创建独立的 Python 环境并安装 mlx-vlm，之后不再需要联网。"),
            ("选择模型", "选一个本地模型", "划词翻译、字幕翻译和会议纪要共用这个常驻模型，之后可以随时更换。"),
            ("授权", "允许 LingoLens 工作", "辅助功能用于读取选中文字，麦克风与系统音频用于转写。授权后无需重启。"),
            ("试一试", "一切准备就绪", "在任意应用中选中一段文字，按下快捷键即可翻译。"),
        ]
    }

    var body: some View {
        HStack(spacing: 0) {
            stepRail
                .frame(width: 176)
                .background(Color.secondary.opacity(0.05))

            Divider()

            VStack(spacing: 0) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                Divider()
                footer
                    .padding(.horizontal, 22)
                    .padding(.vertical, 14)
            }
        }
        .frame(width: 820, height: 540)
        .sheet(isPresented: $showDownload) {
            DownloadSheet(state: environment.downloadState, environment: environment)
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.folder]) { result in
            if case let .success(url) = result {
                Task { await environment.importModel(at: url) }
            }
        }
    }

    // MARK: - 步骤轨

    private var stepRail: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 10) {
                    VStack(spacing: 0) {
                        ZStack {
                            Circle()
                                .fill(index < step ? Color.accentColor : (index == step ? Color.accentColor : Color.secondary.opacity(0.18)))
                                .frame(width: 22, height: 22)
                            if index < step {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                            } else {
                                Text("\(index + 1)")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(index == step ? .white : .secondary)
                            }
                        }
                        if index < steps.count - 1 {
                            Rectangle()
                                .fill(index < step ? Color.accentColor.opacity(0.4) : Color.secondary.opacity(0.2))
                                .frame(width: 1, height: 30)
                        }
                    }

                    Text(item.label)
                        .font(.system(size: 12, weight: index == step ? .semibold : .regular))
                        .foregroundStyle(index == step ? .primary : .secondary)
                        .padding(.top, 3)

                    Spacer(minLength: 0)
                }
            }

            Spacer()
        }
        .padding(.top, 26)
        .padding(.horizontal, 16)
    }

    // MARK: - 内容

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepGraphic
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 26)

            Text("第 \(step + 1) 步，共 \(steps.count) 步")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)

            VStack(alignment: .leading, spacing: 6) {
                Text(steps[step].title)
                    .font(.system(size: 20, weight: .semibold))
                Text(steps[step].summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            stepDetail

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
    }

    @ViewBuilder
    private var stepGraphic: some View {
        switch step {
        case 0:
            Image("BrandIcon")
                .resizable()
                .interpolation(.high)
                .frame(width: 74, height: 74)
        case 4:
            HStack(spacing: 8) {
                keyCap("⌥")
                keyCap("D")
            }
        default:
            Image(systemName: step == 1 ? "shippingbox" : step == 2 ? "square.stack.3d.up" : "checkmark.shield")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tint)
        }
    }

    private func keyCap(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 18, weight: .medium, design: .rounded))
            .frame(minWidth: 38, minHeight: 34)
            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.secondary.opacity(0.2)))
    }

    @ViewBuilder
    private var stepDetail: some View {
        switch step {
        case 1:
            runtimeDetail
        case 2:
            modelDetail
        case 3:
            PermissionsSettingsView()
                .padding(12)
                .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
        case 4:
            HStack(spacing: 10) {
                Text("快捷键")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(environment.hotkeyDisplay)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
                Button("打开翻译浮窗试一试") {
                    environment.coordinator.openManualPanel()
                }
                .controlSize(.small)
                Spacer()
            }
            .padding(.top, 4)
        default:
            EmptyView()
        }
    }

    private var runtimeDetail: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(environment.runtimeProgress.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    if let detail = environment.runtimeProgress.detail {
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                if environment.runtimeInstalled {
                    Label("已就绪", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.success)
                } else if environment.isInstallingRuntime {
                    Button("取消") { environment.cancelRuntimeInstall() }
                        .controlSize(.small)
                } else {
                    // 失败后重试要复用已下载的包，不能 force 重置环境。
                    Button(environment.runtimeProgress.phase == .failed ? "重试" : "安装") {
                        Task { await environment.installRuntime() }
                    }
                    .controlSize(.small)
                }
            }

            if !environment.runtimeInstalled {
                if let fraction = environment.runtimeProgress.fraction {
                    ProgressView(value: fraction)
                } else {
                    ProgressView().progressViewStyle(.linear)
                }
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }

    private var modelDetail: some View {
        VStack(alignment: .leading, spacing: 8) {
            if environment.models.filter(\.isAvailable).isEmpty {
                Text("还没有可用的本地模型。推荐下载 Qwen3 4B（约 2.7 GB），或扫描已有的 MLX 模型文件夹。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Button {
                        showDownload = true
                    } label: {
                        Label("从 Hugging Face 下载…", systemImage: "arrow.down.circle")
                    }
                    Button {
                        isImporting = true
                    } label: {
                        Label("导入本地文件夹…", systemImage: "folder.badge.plus")
                    }
                    Spacer()
                }
            } else {
                VStack(spacing: 6) {
                    ForEach(environment.models.filter(\.isAvailable)) { record in
                        Button {
                            environment.setResidentModelID(record.id)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: isResident(record) ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(isResident(record) ? Color.accentColor : .secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(record.name)
                                            .font(.system(size: 12, weight: .medium))
                                        if isRecommended(record) {
                                            TagBadge(text: "推荐", color: .accentColor)
                                        }
                                    }
                                    if let info = record.info {
                                        Text(info.summary)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(isResident(record) ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.04))
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(record.path)
                    }
                }

                HStack(spacing: 8) {
                    Button("下载另一个…") { showDownload = true }
                        .controlSize(.small)
                    Button("导入文件夹…") { isImporting = true }
                        .controlSize(.small)
                    Spacer()
                }
            }
        }
    }

    private func isResident(_ record: ModelRecord) -> Bool {
        environment.settings.residentModelID == record.id
    }

    /// 4B 的 4-bit 量化版本是默认推荐；8-bit 版本更占内存，不标推荐。
    private func isRecommended(_ record: ModelRecord) -> Bool {
        record.name.lowercased().contains("qwen3.5-4b")
            && (record.info?.quantizationBits ?? 4) == 4
    }

    // MARK: - 底部

    private var footer: some View {
        HStack(spacing: 10) {
            if step > 0 {
                Button("返回") { step -= 1 }
            }

            Spacer()

            Button("跳过引导") { finish() }
                .buttonStyle(.link)
                .font(.caption)

            Button(step == steps.count - 1 ? "进入 LingoLens" : "继续") {
                if step == steps.count - 1 {
                    finish()
                } else {
                    step += 1
                }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(!canContinue)
        }
    }

    private var canContinue: Bool {
        switch step {
        case 1: return environment.runtimeInstalled
        case 2: return environment.residentModel != nil || environment.models.contains(where: \.isAvailable)
        default: return true
        }
    }

    private func finish() {
        environment.finishOnboarding()
        dismiss()
    }
}
