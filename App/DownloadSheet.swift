import ModelLibrary
import ModelRuntime
import SwiftUI

struct DownloadSheet: View {
    @ObservedObject var state: ModelDownloadState
    let environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("从 Hugging Face 下载模型")
                .font(.title3.bold())
            Text("支持公开仓库，文件会下载到 ~/Library/Application Support/LingoLens/models/，支持断点续传。关闭这个面板不会中断下载。")
                .font(.callout)
                .foregroundStyle(.secondary)

            TextField("mlx-community/Qwen3.5-4B-MLX-4bit", text: $state.repoID)
                .textFieldStyle(.roundedBorder)
                .disabled(state.isDownloading)

            if state.isDownloading || state.isPaused {
                if let progress = state.progress {
                    ProgressView(value: progress.fileFraction ?? 0)
                    HStack {
                        Text("文件 \(progress.fileIndex + 1)/\(progress.fileCount) · \(progress.currentFile)")
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(state.isPaused ? "已暂停" : transferText(progress))
                            .monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else if state.isDownloading {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("正在获取文件列表…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if case let .failed(message) = state.phase {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(Color.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("关闭") { dismiss() }
                Button(state.isPaused ? "继续下载" : "开始下载") {
                    if state.isPaused {
                        state.resume(environment: environment)
                    } else {
                        state.start(environment: environment)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    state.repoID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || state.isDownloading
                )
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private func transferText(_ progress: DownloadProgress) -> String {
        var parts = [formatBytes(UInt64(max(0, progress.fileBytesDownloaded)))]
        if let total = progress.fileTotalBytes {
            parts[0] += " / " + formatBytes(UInt64(max(0, total)))
        }
        if let speed = state.bytesPerSecond, speed > 0 {
            parts.append(formatBytes(UInt64(speed)) + "/s")
        }
        if let remaining = state.remainingSeconds {
            parts.append(remaining < 60 ? "本文件剩余 \(Int(remaining)) 秒" : "本文件剩余约 \(Int(remaining / 60) + 1) 分钟")
        }
        return parts.joined(separator: " · ")
    }
}
