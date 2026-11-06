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
    /// 0...1，未知时为 nil。
    public let fraction: Double?

    public init(phase: InstallPhase, message: String, fraction: Double? = nil) {
        self.phase = phase
        self.message = message
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

/// 基于 `Process` 的实现。
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

        try process.run()

        return await withCheckedContinuation { (continuation: CheckedContinuation<Int32, Never>) in
            process.terminationHandler = { finished in
                pipes.closeReadableEnds()
                collector.flush()
                continuation.resume(returning: finished.terminationStatus)
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

private final class OutputTail: @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private var text = ""

    init(limit: Int) {
        self.limit = limit
    }

    func append(_ line: String) {
        lock.lock()
        text += line + "\n"
        if text.count > limit {
            text = String(text.suffix(limit))
        }
        lock.unlock()
    }

    var value: String {
        lock.lock()
        defer { lock.unlock() }
        return text
    }
}

/// 应用托管的 Python 环境：使用内置 uv 创建 venv 并安装固定版本的 mlx-vlm。
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
    private var installTask: Task<URL, Error>?
    private var continuations: [UUID: AsyncStream<InstallProgress>.Continuation] = [:]
    private(set) public var lastProgress: InstallProgress = .init(phase: .idle, message: "")

    public init(
        paths: RuntimePaths,
        spec: RuntimeSpec = .default,
        runner: any CommandRunning = ProcessCommandRunner(),
        uvLocator: @escaping @Sendable () -> URL? = PythonEnvironment.defaultUVLocator
    ) {
        self.paths = paths
        self.spec = spec
        self.runner = runner
        self.uvLocator = uvLocator
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

    /// 删除环境，用于手工重装。
    public func reset() throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: paths.runtimeDirectory.path) {
            try fileManager.removeItem(at: paths.runtimeDirectory)
        }
        try paths.prepare()
        emit(.init(phase: .idle, message: "环境已清除"))
    }

    private func performInstall() async throws -> URL {
        try paths.prepare()

        guard let uv = uvLocator() else {
            let progress = InstallProgress(phase: .failed, message: "未找到 uv")
            emit(progress)
            throw RuntimeError.uvNotFound
        }

        emit(.init(phase: .preparing, message: "准备 Python \(spec.pythonVersion) 环境", fraction: 0.05))

        let venvResult = try await runCommand(
            uv,
            ["venv", paths.runtimeDirectory.appendingPathComponent("venv").path, "--python", spec.pythonVersion],
            phase: .creatingEnvironment
        )
        guard venvResult == 0 else {
            throw RuntimeError.commandFailed(command: "uv venv", exitCode: venvResult, output: collectedOutput)
        }

        emit(.init(phase: .installingDependencies, message: "安装 mlx-vlm \(spec.mlxVLMVersion)", fraction: 0.25))

        let installExit = try await runCommand(
            uv,
            ["pip", "install", "--python", paths.pythonExecutable.path, "mlx-vlm==\(spec.mlxVLMVersion)"],
            phase: .installingDependencies
        )
        guard installExit == 0 else {
            throw RuntimeError.commandFailed(command: "uv pip install mlx-vlm", exitCode: installExit, output: collectedOutput)
        }

        emit(.init(phase: .verifying, message: "校验运行时", fraction: 0.9))

        guard FileManager.default.isExecutableFile(atPath: paths.pythonExecutable.path) else {
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

    private var collectedOutput = ""

    private func runCommand(_ executable: URL, _ arguments: [String], phase: InstallPhase) async throws -> Int32 {
        let tail = OutputTail(limit: 4000)
        let exitCode = try await runner.run(executable: executable, arguments: arguments, environment: nil) { line in
            tail.append(line)
        }
        collectedOutput = tail.value
        emit(.init(phase: phase, message: phase == .creatingEnvironment ? "创建虚拟环境" : "安装依赖", fraction: nil))
        return exitCode
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
