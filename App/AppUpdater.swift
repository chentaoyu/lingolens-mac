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
    /// 发现的新版本号；nil 表示当前已是最新（或还没检查过）。
    /// 菜单栏用它做「有新版本」的醒目提示。
    @Published private(set) var availableUpdateVersion: String?

    private var controller: SPUStandardUpdaterController?
    private var candidates: [URL] = []
    private var attempted: Set<String> = []
    private var forcedURL: URL?
    private var downloadFailed = false
    private var retryTask: Task<Void, Never>?
    /// 本轮检查是否已发现新版本，用于区分「已是最新」和「有更新」。
    private var foundUpdateThisCycle = false

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
        attempted = []
        forcedURL = nil
        AppLog.write("[update] 候选下载源：\(urls.map { $0.host ?? "?" })")
    }

    // MARK: - SPUUpdaterDelegate

    /// 开发期把 appcast 指到本地/测试源，用于验证更新流程与新版本提示。
    /// LINGOLENS_FEED_URL=https://localhost:8765/appcast.xml
    func feedURLString(for updater: SPUUpdater) -> String? {
        ProcessInfo.processInfo.environment["LINGOLENS_FEED_URL"]
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        downloadFailed = false
        foundUpdateThisCycle = true
        availableUpdateVersion = item.displayVersionString
        AppLog.write("[update] 发现新版本 \(item.displayVersionString)")
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
        // 按候选顺序依次尝试：第一个就是镜像，官方排最后兜底。
        let target = forcedURL
            ?? candidates.first(where: { !attempted.contains($0.absoluteString) })
            ?? official
        forcedURL = nil
        attempted.insert(target.absoluteString)
        lastSourceHost = target.host

        AppLog.write("[update] 下载源 \(target.host ?? "?")（第 \(attempted.count)/\(candidates.count) 个候选）")
        if target.absoluteString != official.absoluteString {
            request.url = target
        }
    }

    func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        AppLog.write("[update] 下载完成（\(lastSourceHost ?? "?")）")
        attempted = []
        downloadFailed = false
        retryTask?.cancel()
        retryTask = nil
    }

    func updater(_ updater: SPUUpdater, failedToDownloadUpdate item: SUAppcastItem, error: any Error) {
        downloadFailed = true
        AppLog.write(
            "[update] 下载失败（\(lastSourceHost ?? "?"))：\(error.localizedDescription)"
        )
        // 不依赖 update cycle 结束回调：那条路径只触发一次，实测会漏掉后面的候选源。
        scheduleRetryFromFailure()
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        AppLog.write("[update] cycle 结束 error=\(error.map { $0.localizedDescription } ?? "nil") 已试=\(attempted.count)/\(candidates.count)")
        // 这一轮没发现新版本（且没报错）就清掉提示。
        if !foundUpdateThisCycle, error == nil {
            availableUpdateVersion = nil
        }
        foundUpdateThisCycle = false
        // 兜底：失败回调没被调到时，这里再推一次。
        if error != nil, downloadFailed {
            scheduleRetryFromFailure()
        }
    }

    // MARK: - 换源重试

    /// 换到下一个还没试过的源并重新发起检查；候选用尽就停下并提示。
    private func scheduleRetryFromFailure() {
        guard retryTask == nil else { return }
        guard let next = candidates.first(where: { !attempted.contains($0.absoluteString) }) else {
            downloadFailed = false
            AppLog.write("[update] 所有候选源都失败了：\(candidates.map { $0.host ?? "?" })")
            AppEnvironment.shared.showToast(
                AppToast(
                    title: "更新下载失败",
                    subtitle: "已尝试全部下载源。可在「设置 → 通用 → 更新」换自定义地址，或到发布页手动下载。",
                    systemImage: "exclamationmark.triangle.fill"
                ),
                autoDismissAfter: 10
            )
            return
        }

        downloadFailed = false
        forcedURL = next
        AppLog.write("[update] 换源重试：\(next.host ?? "?")")
        AppEnvironment.shared.showToast(
            AppToast(
                title: "更新下载失败，正在换源重试",
                subtitle: "改用 \(next.host ?? "其他源")",
                systemImage: "arrow.triangle.2.circlepath"
            ),
            autoDismissAfter: 8
        )

        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            guard let self, let controller = self.controller else { return }
            await MainActor.run {
                self.retryTask = nil
                controller.updater.checkForUpdatesInBackground()
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
