import Foundation
import ModelLibrary

/// 模型下载的共享状态：模型页的页内下载卡、引导页和「下载模型」面板共用同一份进度。
/// 暂停通过取消任务实现，HFDownloader 会保留 .part 文件，继续时自动续传。
@MainActor
final class ModelDownloadState: ObservableObject {
    enum Phase: Equatable {
        case idle
        case downloading
        case paused
        case finished(String)
        case failed(String)
    }

    @Published var repoID: String = ""
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var progress: DownloadProgress?
    @Published private(set) var bytesPerSecond: Double?

    private var lastSample: (file: Int, bytes: Int64, time: Date)?
    private var task: Task<Void, Never>?

    /// 卡片是否需要显示（有下载任务、已暂停、刚完成或失败）。
    var isActive: Bool {
        switch phase {
        case .idle: return false
        case .downloading, .paused, .finished, .failed: return true
        }
    }

    var isDownloading: Bool {
        if case .downloading = phase { return true }
        return false
    }

    var isPaused: Bool {
        if case .paused = phase { return true }
        return false
    }

    /// 当前文件剩余时间；没有总大小或速度时为 nil。
    var remainingSeconds: Double? {
        guard let progress, let total = progress.fileTotalBytes,
              let speed = bytesPerSecond, speed > 0 else { return nil }
        return Double(max(0, total - progress.fileBytesDownloaded)) / speed
    }

    func start(environment: AppEnvironment) {
        let repo = repoID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !repo.isEmpty, !isDownloading else { return }
        repoID = repo
        phase = .downloading
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
                self.phase = .finished(record.name)
                self.bytesPerSecond = nil
                self.progress = nil
            } catch is CancellationError {
                // 暂停与取消由 pause()/cancel() 决定最终状态，这里不覆盖。
            } catch {
                self.phase = .failed(error.localizedDescription)
                self.bytesPerSecond = nil
            }
        }
    }

    func pause() {
        guard isDownloading else { return }
        phase = .paused
        task?.cancel()
        task = nil
    }

    func resume(environment: AppEnvironment) {
        guard isPaused else { return }
        phase = .downloading
        start(environment: environment)
    }

    func cancel() {
        task?.cancel()
        task = nil
        phase = .idle
        progress = nil
        bytesPerSecond = nil
        lastSample = nil
    }

    func dismissCard() {
        guard !isDownloading else { return }
        cancel()
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
}
