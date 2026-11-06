import AppKit
import Combine
import Foundation
import Settings
import Sparkle

/// Sparkle 2 自动更新的薄封装：启动时按 Info.plist 配置自动检查，并提供手动"检查更新"。
///
/// 更新包默认从 GitHub Releases 下载，国内经常超时或中断，因此这里做了两件事：
/// 1. 发现新版本后并行测速「官方地址 + 内置加速镜像」，下载时把请求改写到最快的可用源；
/// 2. 下载失败后自动换下一个源重试。
/// 完整性由 appcast 里的 EdDSA 签名保证：镜像即使被篡改，Sparkle 也会拒绝安装。
@MainActor
final class AppUpdater: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let shared = AppUpdater()

    @Published private(set) var canCheckForUpdates = false
    /// 最近一次实际使用的下载源 host（排查用）。
    @Published private(set) var lastSourceHost: String?

    private var controller: SPUStandardUpdaterController?
    private var candidates: [URL] = []
    private var speeds: [URL: Double] = [:]
    private var attempted: Set<String> = []
    private var forcedURL: URL?
    private var probeTask: Task<Void, Never>?
    private var downloadFailed = false

    private override init() {
        super.init()
        let controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        self.controller = controller
        controller.startUpdater()
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        // 菜单栏应用默认不在前台，先激活，否则更新窗口会被别的应用挡住。
        NSApp.activate()
        controller?.checkForUpdates(nil)
    }

    /// 形如 "v0.1.2 (2)"。
    static var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "v\(version) (\(build))"
    }

    // MARK: - 选源

    private func refreshCandidates(official: URL) {
        let settings = AppEnvironment.shared.settings.update
        let urls = UpdateDownloadResolver.candidates(official: official, settings: settings)
        guard urls != candidates else { return }

        candidates = urls
        speeds = [:]
        attempted = []
        forcedURL = nil
        probeTask?.cancel()

        guard urls.count > 1 else {
            probeTask = nil
            return
        }
        probeTask = Task { [weak self] in
            let measured = await UpdateSourceProbe.measure(urls)
            guard !Task.isCancelled else { return }
            self?.speeds = measured
        }
    }

    // MARK: - SPUUpdaterDelegate

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        downloadFailed = false
        guard let official = item.fileURL else { return }
        refreshCandidates(official: official)
    }

    func updater(
        _ updater: SPUUpdater,
        willDownloadUpdate item: SUAppcastItem,
        with request: NSMutableURLRequest
    ) {
        guard let official = item.fileURL else { return }
        if candidates.isEmpty {
            refreshCandidates(official: official)
        }
        let target = forcedURL ?? UpdateDownloadResolver.choose(
            candidates: candidates,
            measuredBytesPerSecond: speeds,
            official: official
        )
        forcedURL = nil
        attempted.insert(target.absoluteString)
        lastSourceHost = target.host

        if target.absoluteString != official.absoluteString {
            request.url = target
            print("[Updater] 改用加速源下载：\(target.absoluteString)")
        }
    }

    func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        attempted = []
        downloadFailed = false
    }

    func updater(_ updater: SPUUpdater, failedToDownloadUpdate item: SUAppcastItem, error: any Error) {
        downloadFailed = true
        print("[Updater] 更新下载失败（\(lastSourceHost ?? "?"))：\(error.localizedDescription)")
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        guard error != nil, downloadFailed else { return }
        downloadFailed = false
        guard let next = candidates.first(where: { !attempted.contains($0.absoluteString) }) else {
            return
        }

        forcedURL = next
        AppEnvironment.shared.showToast(
            AppToast(
                title: "更新下载失败，正在换源重试",
                subtitle: "改用 \(next.host ?? "其他源")；如果仍然失败，可在 设置 → 通用 → 更新 里换下载源",
                systemImage: "arrow.triangle.2.circlepath"
            ),
            autoDismissAfter: 8
        )

        let inBackground = updateCheck == .updatesInBackground
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, let controller = self.controller else { return }
            if inBackground {
                controller.updater.checkForUpdatesInBackground()
            } else {
                self.checkForUpdates()
            }
        }
    }
}

/// 更新源测速：小范围请求，按实际吞吐排序。
enum UpdateSourceProbe {
    static func measure(
        _ urls: [URL],
        sampleBytes: Int = 64 * 1024,
        timeout: TimeInterval = 4
    ) async -> [URL: Double] {
        await withTaskGroup(of: (URL, Double?).self) { group in
            for url in urls {
                group.addTask { (url, await measureOne(url, sampleBytes: sampleBytes, timeout: timeout)) }
            }
            var results: [URL: Double] = [:]
            for await (url, speed) in group {
                if let speed, speed > 0 { results[url] = speed }
            }
            return results
        }
    }

    private static func measureOne(_ url: URL, sampleBytes: Int, timeout: TimeInterval) async -> Double? {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue("bytes=0-\(sampleBytes - 1)", forHTTPHeaderField: "Range")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }

        let started = Date()
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode)
            else { return nil }

            var received = 0
            for try await _ in bytes {
                received += 1
                if received >= sampleBytes { break }
            }
            guard received > 0 else { return nil }
            let elapsed = max(Date().timeIntervalSince(started), 0.05)
            return Double(received) / elapsed
        } catch {
            return nil
        }
    }
}
