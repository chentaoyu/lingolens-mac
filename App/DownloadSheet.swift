import ModelLibrary
import ModelRuntime
import SwiftUI

@MainActor
final class DownloadSheetModel: ObservableObject {
    enum State: Equatable {
        case idle
        case downloading
        case finished(String)
        case failed(String)
    }

    @Published var repoID: String = ""
    @Published private(set) var state: State = .idle
    @Published private(set) var progress: DownloadProgress?
    /// 当前文件的下载速度（字节/秒），按最近的采样平滑。
    @Published private(set) var bytesPerSecond: Double?

    private var lastSample: (file: Int, bytes: Int64, time: Date)?

    private var task: Task<Void, Never>?

    func start(environment: AppEnvironment) {
        let repo = repoID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !repo.isEmpty else { return }
        state = .downloading
        progress = nil
        bytesPerSecond = nil
        lastSample = nil

        task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let record = try await environment.downloadModel(repoID: repo) { progress in
                    Task { @MainActor in
                        self.record(progress)
                    }
                }
                state = .finished(record.name)
            } catch is CancellationError {
                state = .idle
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    private func record(_ progress: DownloadProgress) {
        let now = Date()
        if let last = lastSample, last.file == progress.fileIndex {
            let elapsed = now.timeIntervalSince(last.time)
            // 采样间隔太短时跳过，避免速度跳动。
            guard elapsed >= 0.5 else {
                self.progress = progress
                return
            }
            let speed = Double(progress.fileBytesDownloaded - last.bytes) / elapsed
            bytesPerSecond = bytesPerSecond.map { $0 * 0.6 + speed * 0.4 } ?? speed
        } else if lastSample?.file != progress.fileIndex {
            bytesPerSecond = nil
        }
        lastSample = (progress.fileIndex, progress.fileBytesDownloaded, now)
        self.progress = progress
    }

    /// 当前文件剩余时间；没有总大小或速度时为 nil。
    var remainingSeconds: Double? {
        guard let progress, let total = progress.fileTotalBytes, let speed = bytesPerSecond, speed > 0 else { return nil }
        return Double(max(0, total - progress.fileBytesDownloaded)) / speed
    }

    func cancel() {
        task?.cancel()
        task = nil
        state = .idle
    }
}

struct DownloadSheet: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = DownloadSheetModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("从 Hugging Face 下载模型")
                .font(.title3.bold())
            Text("支持公开仓库，文件会下载到 ~/Library/Application Support/LingoLens/models/，支持断点续传。")
                .font(.callout)
                .foregroundStyle(.secondary)

            TextField("mlx-community/Qwen3.5-4B-MLX-4bit", text: $model.repoID)
                .textFieldStyle(.roundedBorder)
                .disabled(model.state == .downloading)

            if model.state == .downloading {
                if let progress = model.progress {
                    ProgressView(value: progress.fileFraction ?? 0)
                    HStack {
                        Text("文件 \(progress.fileIndex + 1)/\(progress.fileCount) · \(progress.currentFile)")
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(transferText(progress))
                            .monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("正在获取文件列表…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if case let .finished(name) = model.state {
                Label("已下载 \(name)", systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.green)
            }

            if case let .failed(message) = model.state {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("关闭") {
                    model.cancel()
                    dismiss()
                }
                Button("开始下载") {
                    model.start(environment: environment)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    model.repoID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || model.state == .downloading
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
        if let speed = model.bytesPerSecond, speed > 0 {
            parts.append(formatBytes(UInt64(speed)) + "/s")
        }
        if let remaining = model.remainingSeconds {
            parts.append(remaining < 60 ? "本文件剩余 \(Int(remaining)) 秒" : "本文件剩余约 \(Int(remaining / 60) + 1) 分钟")
        }
        return parts.joined(separator: " · ")
    }
}
