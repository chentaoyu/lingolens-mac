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

    private var task: Task<Void, Never>?

    func start(environment: AppEnvironment) {
        let repo = repoID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !repo.isEmpty else { return }
        state = .downloading
        progress = nil

        task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let record = try await environment.downloadModel(repoID: repo) { progress in
                    Task { @MainActor in
                        self.progress = progress
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
                    Text("\(progress.fileIndex + 1)/\(progress.fileCount) · \(progress.currentFile) · \(formatBytes(UInt64(max(0, progress.fileBytesDownloaded))))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
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
}
