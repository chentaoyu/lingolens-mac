import Foundation

public enum InstallPhase: String, Sendable, Equatable {
    case idle
    case preparing
    case creatingEnvironment
    case installingDependencies
    case verifying
    case ready
    case failed
}

public struct InstallProgress: Sendable, Equatable {
    public let phase: InstallPhase
    public let message: String
    /// 第二行说明：当前下载的包、体积、下载源或排障提示。
    public let detail: String?
    /// 0...1，未知时为 nil。
    public let fraction: Double?

    public init(phase: InstallPhase, message: String, detail: String? = nil, fraction: Double? = nil) {
        self.phase = phase
        self.message = message
        self.detail = detail
        self.fraction = fraction
    }
}

/// 运行外部命令的抽象，便于在测试中 mock。
public protocol CommandRunning: Sendable {
    func run(
        executable: URL,
        arguments: [String],
        environment: [String: String]?,
        lineHandler: (@Sendable (String) -> Void)?
    ) async throws -> Int32
}

public extension CommandRunning {
    func run(executable: URL, arguments: [String], environment: [String: String]? = nil) async throws -> Int32 {
        try await run(executable: executable, arguments: arguments, environment: environment, lineHandler: nil)
    }
}

/// 基于 `Process` 的实现。任务取消时向子进程发 SIGTERM，避免安装中途只能强杀 App。
public struct ProcessCommandRunner: CommandRunning {
    public init() {}

    public func run(
        executable: URL,
        arguments: [String],
        environment: [String: String]?,
        lineHandler: (@Sendable (String) -> Void)?
    ) async throws -> Int32 {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let environment {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        }

        let pipes = PipePair()
        process.standardOutput = pipes.output
        process.standardError = pipes.error

        let collector = LineCollector(handler: lineHandler)
        pipes.output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { return }
            collector.consume(data)
        }
        pipes.error.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { return }
            collector.consume(data)
        }

        return try await withTaskCancellationHandler {
            try process.run()
            return await withCheckedContinuation { (continuation: CheckedContinuation<Int32, Never>) in
                process.terminationHandler = { finished in
                    pipes.closeReadableEnds()
                    collector.flush()
                    continuation.resume(returning: finished.terminationStatus)
                }
            }
        } onCancel: {
            if process.isRunning {
                process.terminate()
            }
        }
    }
}

private final class PipePair: @unchecked Sendable {
    let output = Pipe()
    let error = Pipe()

    func closeReadableEnds() {
        output.fileHandleForReading.readabilityHandler = nil
        error.fileHandleForReading.readabilityHandler = nil
    }
}

private final class LineCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private let handler: (@Sendable (String) -> Void)?

    init(handler: (@Sendable (String) -> Void)?) {
        self.handler = handler
    }

    func consume(_ data: Data) {
        var lines: [String] = []
        lock.lock()
        buffer.append(data)
        while let index = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[buffer.startIndex..<index]
            buffer.removeSubrange(buffer.startIndex...index)
            if let line = String(data: lineData, encoding: .utf8) {
                lines.append(line)
            }
        }
        lock.unlock()
        for line in lines {
            handler?(line)
        }
    }

    func flush() {
        lock.lock()
        let remainder = buffer
        buffer.removeAll()
        lock.unlock()
        if !remainder.isEmpty, let line = String(data: remainder, encoding: .utf8) {
            handler?(line)
        }
    }
}

/// 收集 uv 输出：既用于错误信息，也用于把下载进度喂给 UI。
final class InstallOutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var parser = InstallOutputParser()
    private var tail = ""
    private var lastLineAt = Date()

    private let tailLimit = 4000

    func reset() {
        lock.lock()
        parser = InstallOutputParser()
        tail = ""
        lastLineAt = Date()
        lock.unlock()
    }

    func consume(_ line: String) {
        lock.lock()
        parser.consume(line)
        tail += line + "\n"
        if tail.count > tailLimit {
            tail = String(tail.suffix(tailLimit))
        }
        lastLineAt = Date()
        lock.unlock()
    }

    func snapshot() -> (activity: InstallActivity, tail: String, silentFor: TimeInterval, didFail: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (parser.activity, tail, Date().timeIntervalSince(lastLineAt), parser.didFail)
    }

    var errorTail: String {
        lock.lock()
        defer { lock.unlock() }
        return tail
    }
}

/// 应用托管的 Python 环境：使用内置 uv 创建 venv 并安装固定版本的 mlx-vlm。
///
/// 首次安装要下载 70+ 个包（约 220MB），因此这里做了三件事：
/// 1. 默认走国内镜像，失败自动回退官方 PyPI；
/// 2. 把 uv 的输出解析成可读进度（当前包、已下载数量、已用时间、卡住提示）；
/// 3. 固定 uv 缓存目录 + 可取消，避免中断后从头再来。
public actor PythonEnvironment {
    public struct Marker: Codable, Sendable, Equatable {
        public var pythonVersion: String
        public var mlxVLMVersion: String
        public var installedAt: Date

        public init(pythonVersion: String, mlxVLMVersion: String, installedAt: Date) {
            self.pythonVersion = pythonVersion
            self.mlxVLMVersion = mlxVLMVersion
            self.installedAt = installedAt
        }
    }

    private let paths: RuntimePaths
    private let spec: RuntimeSpec
    private let runner: any CommandRunning
    private let uvLocator: @Sendable () -> URL?
    private var configuration: InstallConfiguration = .default
    private var installTask: Task<URL, Error>?
    private var continuations: [UUID: AsyncStream<InstallProgress>.Continuation] = [:]
    private(set) public var lastProgress: InstallProgress = .init(phase: .idle, message: "")

    private var collector: InstallOutputCollector?
    private var ticker: Task<Void, Never>?
    private var installStartedAt = Date()
    private var currentPhase: InstallPhase = .idle
    private var currentSourceLabel: String?

    /// 超过这个时长没有新输出就认为网络卡住了，在界面上给出提示。
    private let stallThreshold: TimeInterval = 45

    public init(
        paths: RuntimePaths,
        spec: RuntimeSpec = .default,
        runner: any CommandRunning = ProcessCommandRunner(),
        configuration: InstallConfiguration = .default,
        uvLocator: @escaping @Sendable () -> URL? = PythonEnvironment.defaultUVLocator
    ) {
        self.paths = paths
        self.spec = spec
        self.runner = runner
        self.configuration = configuration
        self.uvLocator = uvLocator
    }

    /// 设置里的下载源/代理变化后调用；下一次安装生效。
    public func update(configuration: InstallConfiguration) {
        self.configuration = configuration
    }

    public func currentConfiguration() -> InstallConfiguration {
        configuration
    }

    /// 安装进度流。多次订阅各自独立；晚订阅者会立刻收到最近一次进度。
    public func progressStream() -> AsyncStream<InstallProgress> {
        let id = UUID()
        return AsyncStream { continuation in
            continuation.yield(lastProgress)
            continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(id) }
            }
        }
    }

    public func installedMarker() -> Marker? {
        guard let data = try? Data(contentsOf: paths.installationMarker) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Marker.self, from: data)
    }

    public func isInstalled() -> Bool {
        guard let marker = installedMarker() else { return false }
        guard marker.pythonVersion == spec.pythonVersion, marker.mlxVLMVersion == spec.mlxVLMVersion else {
            return false
        }
        return FileManager.default.isExecutableFile(atPath: paths.pythonExecutable.path)
    }

    /// 确保环境存在，返回 python 解释器路径。并发调用共享同一个安装任务。
    ///
    /// 上次安装失败（没有 `installed.json` 或虚拟环境不完整）时这里会重新执行，
    /// uv 缓存和已下载的包会被复用，不会从头再来。
    public func ensureInstalled() async throws -> URL {
        if let existing = installTask {
            return try await existing.value
        }
        if isInstalled() {
            let progress = InstallProgress(phase: .ready, message: "运行时已就绪", fraction: 1)
            emit(progress)
            return paths.pythonExecutable
        }
        let task = Task { try await self.performInstall() }
        installTask = task
        defer { installTask = nil }
        return try await task.value
    }

    /// 取消正在进行的安装（例如用户点「取消」）。
    public func cancelInstall() {
        installTask?.cancel()
    }

    /// 删除环境，用于手工重装。uv 缓存与 Python 解释器保留，重装不必重新下载。
    public func reset() throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: paths.runtimeDirectory.path) {
            try fileManager.removeItem(at: paths.runtimeDirectory)
        }
        try paths.prepare()
        emit(.init(phase: .idle, message: "环境已清除"))
    }

    // MARK: - 安装

    private func performInstall() async throws -> URL {
        try paths.prepare()

        guard let uv = uvLocator() else {
            emit(.init(phase: .failed, message: "未找到 uv"))
            throw RuntimeError.uvNotFound
        }

        let output = InstallOutputCollector()
        collector = output
        installStartedAt = Date()
        currentSourceLabel = nil
        startTicker()
        defer {
            stopTicker()
            collector = nil
            currentPhase = .idle
        }

        emit(.init(phase: .preparing, message: "准备 Python \(spec.pythonVersion) 环境", fraction: 0.05))

        currentPhase = .creatingEnvironment
        let venvExit = try await run(
            uv,
            ["venv", paths.runtimeDirectory.appendingPathComponent("venv").path, "--python", spec.pythonVersion],
            environment: baseEnvironment,
            collector: output
        )
        try checkCancellation(output)
        guard venvExit == 0 else {
            emit(.init(phase: .failed, message: "创建虚拟环境失败", detail: failureDetail(output)))
            throw RuntimeError.commandFailed(command: "uv venv", exitCode: venvExit, output: output.errorTail)
        }

        currentPhase = .installingDependencies
        var lastError: RuntimeError?
        let attempts = configuration.indexAttempts

        for (offset, indexURL) in attempts.enumerated() {
            if offset > 0 {
                currentSourceLabel = indexURL?.host
                emit(.init(
                    phase: .installingDependencies,
                    message: "上一个源失败，改用 \(currentSourceLabel ?? "官方 PyPI") 重试 · 已用 0:00",
                    detail: lastError?.errorDescription,
                    fraction: 0.2
                ))
            } else {
                currentSourceLabel = indexURL?.host
            }
            output.reset()

            var arguments = ["pip", "install", "--python", paths.pythonExecutable.path]
            if let indexURL {
                arguments += ["--index-url", indexURL.absoluteString]
            }
            arguments.append("mlx-vlm==\(spec.mlxVLMVersion)")

            let exit = try await run(uv, arguments, environment: baseEnvironment, collector: output)
            try checkCancellation(output)

            if exit == 0 {
                lastError = nil
                break
            }
            lastError = .commandFailed(
                command: indexURL.map { "uv pip install --index-url \($0.host ?? $0.absoluteString)" } ?? "uv pip install",
                exitCode: exit,
                output: output.errorTail
            )
        }

        if let lastError {
            emit(.init(
                phase: .failed,
                message: "依赖安装失败",
                detail: "可在 设置 → 系统 → 运行时 换一个下载源或填写代理后重试"
            ))
            throw lastError
        }

        currentPhase = .verifying
        emit(.init(phase: .verifying, message: "校验运行时", fraction: 0.95))

        guard FileManager.default.isExecutableFile(atPath: paths.pythonExecutable.path) else {
            emit(.init(phase: .failed, message: "Python 环境不完整"))
            throw RuntimeError.pythonMissing(path: paths.pythonExecutable.path)
        }

        let marker = Marker(pythonVersion: spec.pythonVersion, mlxVLMVersion: spec.mlxVLMVersion, installedAt: Date())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(marker).write(to: paths.installationMarker, options: .atomic)

        emit(.init(phase: .ready, message: "运行时已就绪", fraction: 1))
        return paths.pythonExecutable
    }

    /// uv 子进程的环境变量：网络参数 + 固定缓存目录（重试时复用已下载的包）。
    private var baseEnvironment: [String: String] {
        var environment = configuration.uvEnvironment
        environment["UV_CACHE_DIR"] = paths.uvCacheDirectory.path
        environment["UV_PYTHON_INSTALL_DIR"] = paths.pythonInstallDirectory.path
        return environment
    }

    private func run(
        _ executable: URL,
        _ arguments: [String],
        environment: [String: String],
        collector: InstallOutputCollector
    ) async throws -> Int32 {
        try await runner.run(executable: executable, arguments: arguments, environment: environment) { line in
            collector.consume(line)
        }
    }

    private func checkCancellation(_ output: InstallOutputCollector) throws {
        guard Task.isCancelled else { return }
        emit(.init(phase: .failed, message: "安装已取消", detail: "再次安装会复用已下载的包"))
        throw RuntimeError.cancelled
    }

    private func failureDetail(_ output: InstallOutputCollector) -> String? {
        let lines = output.errorTail
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("error:") || $0.hasPrefix("cause:") }
        guard !lines.isEmpty else { return nil }
        return lines.suffix(2).joined(separator: " ")
    }

    // MARK: - 进度

    private func startTicker() {
        stopTicker()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                await self?.tick()
            }
        }
    }

    private func stopTicker() {
        ticker?.cancel()
        ticker = nil
    }

    private func tick() {
        guard let collector, currentPhase == .installingDependencies || currentPhase == .creatingEnvironment else {
            return
        }
        let snapshot = collector.snapshot()
        guard snapshot.activity != .idle || currentPhase == .installingDependencies else { return }
        emit(makeProgress(activity: snapshot.activity, silentFor: snapshot.silentFor))
    }

    private func makeProgress(activity: InstallActivity, silentFor: TimeInterval) -> InstallProgress {
        let elapsed = Self.durationText(Date().timeIntervalSince(installStartedAt))

        switch currentPhase {
        case .creatingEnvironment:
            var detail = "使用内置 uv 创建 Python \(spec.pythonVersion) 虚拟环境"
            if silentFor > stallThreshold {
                detail += " · 长时间无响应通常是在下载 Python 解释器，网络较慢时可稍等或重试"
            }
            return .init(phase: .creatingEnvironment, message: "准备 Python 环境 · 已用 \(elapsed)", detail: detail, fraction: 0.1)

        case .installingDependencies:
            var message = "下载依赖"
            if let total = activity.totalPackages, activity.installedPackages < total {
                if activity.downloadedPackages > 0 {
                    message += " \(activity.downloadedPackages)/\(total)"
                }
            } else if let total = activity.totalPackages {
                message = "安装 \(total) 个包"
            }
            message += " · 已用 \(elapsed)"

            var details: [String] = []
            if let label = currentSourceLabel { details.append(label) }
            if let current = activity.currentPackage {
                if let bytes = activity.currentPackageBytes {
                    details.append("正在下载 \(current) \(formatBytes(UInt64(bytes)))")
                } else {
                    details.append("正在下载 \(current)")
                }
            }
            if activity.downloadedBytes > 0, activity.knownBytes > 0 {
                details.append("已下载 \(formatBytes(UInt64(activity.downloadedBytes))) / \(formatBytes(UInt64(activity.knownBytes)))")
            }
            if silentFor > stallThreshold {
                details.append("网络较慢，可在 设置 → 系统 → 运行时 换下载源")
            }

            return .init(
                phase: .installingDependencies,
                message: message,
                detail: details.joined(separator: " · "),
                fraction: installFraction(activity)
            )

        default:
            return lastProgress
        }
    }

    /// 已完成的包数为主，已知体积比例为辅，两者取大。
    private func installFraction(_ activity: InstallActivity) -> Double {
        var ratio = 0.0
        if let total = activity.totalPackages, total > 0 {
            let completed = Double(max(activity.downloadedPackages, activity.installedPackages))
            let inFlight = Double(max(0, activity.startedPackages - activity.downloadedPackages)) * 0.4
            ratio = min(1, (completed + inFlight) / Double(total))
        }
        if activity.knownBytes > 0 {
            ratio = max(ratio, min(1, Double(activity.downloadedBytes) / Double(activity.knownBytes)))
        }
        return 0.2 + 0.7 * ratio
    }

    private static func durationText(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let minutes = total / 60
        let rest = total % 60
        return String(format: "%d:%02d", minutes, rest)
    }

    private func emit(_ progress: InstallProgress) {
        lastProgress = progress
        for continuation in continuations.values {
            continuation.yield(progress)
        }
    }

    private func removeContinuation(_ id: UUID) {
        continuations[id] = nil
    }

    /// 依次尝试：Bundle 内置 → `LINGOLENS_UV` → 常见安装路径 → PATH。
    public static func defaultUVLocator() -> URL? {
        let fileManager = FileManager.default
        var candidates: [URL] = []

        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("uv/uv") {
            candidates.append(bundled)
        }
        if let bundled = Bundle.main.url(forResource: "uv", withExtension: nil, subdirectory: "uv") {
            candidates.append(bundled)
        }
        if let flat = Bundle.main.url(forResource: "uv", withExtension: nil) {
            candidates.append(flat)
        }
        if let override = ProcessInfo.processInfo.environment["LINGOLENS_UV"] {
            candidates.append(URL(fileURLWithPath: override))
        }

        let home = fileManager.homeDirectoryForCurrentUser
        candidates.append(contentsOf: [
            URL(fileURLWithPath: "/opt/homebrew/bin/uv"),
            URL(fileURLWithPath: "/usr/local/bin/uv"),
            home.appendingPathComponent(".local/bin/uv"),
            home.appendingPathComponent(".cargo/bin/uv")
        ])

        if let pathValue = ProcessInfo.processInfo.environment["PATH"] {
            for directory in pathValue.split(separator: ":") {
                candidates.append(URL(fileURLWithPath: String(directory)).appendingPathComponent("uv"))
            }
        }

        return candidates.first { fileManager.isExecutableFile(atPath: $0.path) }
    }
}
