import ModelLibrary
import ModelRuntime
import SwiftUI

struct DownloadSheet: View {
    @ObservedObject var state: ModelDownloadState
    let environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    @StateObject private var search = ModelSearchViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("下载模型")
                    .font(.title3.bold())
                Text("从魔搭搜索并下载。文件存到 ~/Library/Application Support/LingoLens/models/，支持断点续传，关闭面板不会中断。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            searchBar
            resultList

            if state.isDownloading || state.isPaused {
                progressSection
            }

            if case let .failed(message) = state.phase {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(Color.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            footer
        }
        .padding(20)
        .frame(width: 560)
        .onAppear {
            // 打开就给一份默认列表，用户不用先想搜什么。
            if search.models.isEmpty, !search.didSearch {
                search.query = "Qwen3.5-4B-MLX"
                search.search()
            }
            if search.selectedID == nil,
               !state.repoID.isEmpty {
                search.select(RemoteModel(repositoryID: state.repoID))
            }
        }
    }

    // MARK: - 搜索栏

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索模型，例如 Qwen3.5-4B-MLX", text: $search.query)
                .textFieldStyle(.plain)
                .onSubmit { search.search() }
                .disabled(state.isDownloading)
            if search.isLoading {
                ProgressView().controlSize(.small)
            }
            Button("搜索") { search.search() }
                .disabled(
                    search.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || state.isDownloading
                )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.06))
        )
    }

    // MARK: - 结果列表

    private var resultList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(search.models) { model in
                    modelRow(model)
                        .onAppear { search.loadMoreIfNeeded(current: model) }
                }

                if search.isLoadingMore {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("加载更多…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                } else if search.hasMore {
                    Button("加载更多") { search.loadMore() }
                        .buttonStyle(.link)
                        .font(.caption)
                        .padding(.vertical, 6)
                }

                if let message = search.errorMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(Color.danger)
                        .padding(.vertical, 8)
                } else if search.didSearch, !search.isLoading, search.models.isEmpty {
                    Text("没有找到匹配的 MLX 模型，换个关键词试试")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 12)
                }
            }
        }
        .frame(height: 240)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.secondary.opacity(0.2))
        )
    }

    private func modelRow(_ model: RemoteModel) -> some View {
        let isSelected = search.selectedID == model.id
        return Button {
            search.select(model)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)

                VStack(alignment: .leading, spacing: 1) {
                    Text(model.name)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(model.namespace)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 1) {
                    if let size = model.sizeBytes {
                        Text(sizeText(size))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Text("↓ \(model.downloads)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(state.isDownloading)
        .help(model.repositoryID)
    }

    // MARK: - 进度

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 4) {
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
    }

    // MARK: - 底部

    private var footer: some View {
        HStack(spacing: 10) {
            if let selected = search.selectedID {
                Text(selected)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text("选择一个模型")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button("关闭") { dismiss() }
            Button(state.isPaused ? "继续下载" : "开始下载") {
                if state.isPaused {
                    state.resume(environment: environment)
                } else if let selected = search.selectedID {
                    state.repoID = selected
                    state.start(environment: environment)
                }
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(
                search.selectedID == nil
                    || state.isDownloading
            )
        }
    }

    // MARK: - 辅助

    private func sizeText(_ bytes: Int64) -> String {
        if bytes >= 1_000_000_000 {
            return String(format: "%.1f GB", Double(bytes) / 1_000_000_000)
        }
        return String(format: "%.0f MB", Double(bytes) / 1_000_000)
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
