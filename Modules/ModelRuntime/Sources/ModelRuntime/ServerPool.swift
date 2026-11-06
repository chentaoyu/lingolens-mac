import Foundation

/// 指向磁盘上的一个模型目录。
public struct ModelRef: Sendable, Hashable, Codable {
    public let id: String
    public let name: String
    public let directory: URL

    public init(id: String, name: String, directory: URL) {
        self.id = id
        self.name = name
        self.directory = directory
    }
}

public struct ServerLaunchConfig: Sendable, Equatable {
    public var isResident: Bool
    public var idleUnloadMinutes: Int
    public var options: ServerOptions

    public init(isResident: Bool = false, idleUnloadMinutes: Int = 10, options: ServerOptions = ServerOptions()) {
        self.isResident = isResident
        self.idleUnloadMinutes = idleUnloadMinutes
        self.options = options
    }
}

public enum ServerState: Sendable, Equatable {
    case stopped
    case starting
    case ready(URL)
    case stopping
    case failed(String)

    public var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    public var isRunning: Bool {
        switch self {
        case .starting, .ready, .stopping: return true
        case .stopped, .failed: return false
        }
    }

    public var baseURL: URL? {
        if case let .ready(url) = self { return url }
        return nil
    }

    public var failureReason: String? {
        if case let .failed(message) = self { return message }
        return nil
    }
}

public struct ServerLease: Sendable, Hashable {
    /// 应用内部使用的模型 id（模型目录路径）。
    public let modelID: String
    public let baseURL: URL
    /// 服务端 `/v1/models` 返回的模型标识，Chat Completions 请求的 `model` 字段必须使用它。
    public let serverModelID: String

    public init(modelID: String, baseURL: URL, serverModelID: String) {
        self.modelID = modelID
        self.baseURL = baseURL
        self.serverModelID = serverModelID
    }
}

public struct ServerSnapshot: Sendable, Equatable {
    public let model: ModelRef
    public let state: ServerState
    public let pid: Int32?
    public let activeLeases: Int
    public let restartCount: Int
    public let isResident: Bool
    public let lastUsed: Date
}

/// 模型服务进程池：一个模型一个进程，按需启动、空闲卸载、崩溃重启。
public actor ServerPool {
    private struct Entry {
        let model: ModelRef
        var state: ServerState = .stopped
        var process: (any LaunchedProcess)?
        var pid: Int32?
        var startedAt: Date?
        var config: ServerLaunchConfig?
        var serverModelID: String?
        var startTask: Task<URL, Error>?
        var activeLeases: Int = 0
        var restartCount: Int = 0
        var lastRestartAt: Date?
        var intentionalStop: Bool = false
        var lastUsed: Date

        init(model: ModelRef, lastUsed: Date) {
            self.model = model
            self.lastUsed = lastUsed
        }

        var isResident: Bool { config?.isResident ?? false }
    }

    private let paths: RuntimePaths
    private let python: PythonEnvironment
    private let launcher: any ProcessLaunching
    private let health: any HealthChecking
    private let memory: any MemoryProbing
    private let portAllocator: @Sendable () throws -> Int
    private let now: @Sendable () -> Date
    private let memoryEstimator: @Sendable (URL) -> UInt64
    private let readinessTimeout: TimeInterval
    private let readinessPollInterval: TimeInterval
    private let shutdownGracePeriod: TimeInterval
    private let restartWindow: TimeInterval
    private let memoryCheckEnabled: Bool

    private var entries: [String: Entry] = [:]
    private var idleTimer: Task<Void, Never>?
    private var snapshotObserver: (@Sendable ([ServerSnapshot]) -> Void)?

    public init(
        paths: RuntimePaths,
        python: PythonEnvironment,
        launcher: any ProcessLaunching = SystemProcessLauncher(),
        health: any HealthChecking = HTTPServerHealthChecker(),
        memory: any MemoryProbing = SystemMemoryProbe(),
        portAllocator: @escaping @Sendable () throws -> Int = { try FreePortAllocator.allocate() },
        now: @escaping @Sendable () -> Date = { Date() },
        memoryEstimator: @escaping @Sendable (URL) -> UInt64 = { ModelMemoryEstimator.estimatedMemoryBytes(directory: $0) },
        readinessTimeout: TimeInterval = 120,
        readinessPollInterval: TimeInterval = 0.5,
        shutdownGracePeriod: TimeInterval = 5,
        restartWindow: TimeInterval = 300,
        memoryCheckEnabled: Bool = true,
        cleanupStaleProcesses: Bool = true
    ) {
        self.paths = paths
        self.python = python
        self.launcher = launcher
        self.health = health
        self.memory = memory
        self.portAllocator = portAllocator
        self.now = now
        self.memoryEstimator = memoryEstimator
        self.readinessTimeout = readinessTimeout
        self.readinessPollInterval = readinessPollInterval
        self.shutdownGracePeriod = shutdownGracePeriod
        self.restartWindow = restartWindow
        self.memoryCheckEnabled = memoryCheckEnabled
        if cleanupStaleProcesses {
            PIDRegistry(fileURL: paths.pidRegistryFile).terminateStale()
        }
    }

    public func setSnapshotObserver(_ observer: (@Sendable ([ServerSnapshot]) -> Void)?) {
        snapshotObserver = observer
    }

    public func snapshot() -> [ServerSnapshot] {
        entries.values
            .map {
                ServerSnapshot(
                    model: $0.model,
                    state: $0.state,
                    pid: $0.pid,
                    activeLeases: $0.activeLeases,
                    restartCount: $0.restartCount,
                    isResident: $0.isResident,
                    lastUsed: $0.lastUsed
                )
            }
            .sorted { $0.model.id < $1.model.id }
    }

    public func state(for modelID: String) -> ServerState {
        entries[modelID]?.state ?? .stopped
    }

    /// 确保模型服务已就绪并返回 baseURL。使用同一模型的多次调用共享同一个启动过程。
    public func ensure(model: ModelRef, config: ServerLaunchConfig) async throws -> URL {
        if var entry = entries[model.id] {
            if case let .ready(url) = entry.state {
                entry.lastUsed = now()
                entry.config = config
                entries[model.id] = entry
                notify()
                return url
            }
            if case .starting = entry.state, let task = entry.startTask {
                return try await task.value
            }
            if case .stopping = entry.state {
                while case .stopping = (entries[model.id]?.state ?? .stopped) {
                    try? await Task.sleep(for: .milliseconds(50))
                }
            }
            if case .failed = entry.state {
                entry.state = .stopped
                entry.restartCount = 0
                entries[model.id] = entry
            }
        }

        try checkMemory(for: model)

        var entry = entries[model.id] ?? Entry(model: model, lastUsed: now())
        entry.state = .starting
        entry.config = config
        entry.lastUsed = now()
        entry.intentionalStop = false
        entries[model.id] = entry

        let task = Task { try await self.bootstrap(model: model, config: config) }
        entry = entries[model.id] ?? entry
        entry.startTask = task
        entries[model.id] = entry
        notify()

        return try await task.value
    }

    /// 获取一个引用计数租约；租约未释放前，空闲卸载不会关闭该进程。
    public func acquire(model: ModelRef, config: ServerLaunchConfig) async throws -> ServerLease {
        let baseURL = try await ensure(model: model, config: config)
        let serverModelID: String
        if var entry = entries[model.id] {
            entry.activeLeases += 1
            entry.lastUsed = now()
            entries[model.id] = entry
            serverModelID = entry.serverModelID ?? model.directory.path
        } else {
            serverModelID = model.directory.path
        }
        return ServerLease(modelID: model.id, baseURL: baseURL, serverModelID: serverModelID)
    }

    public func release(_ lease: ServerLease) {
        guard var entry = entries[lease.modelID] else { return }
        entry.activeLeases = max(0, entry.activeLeases - 1)
        entry.lastUsed = now()
        entries[lease.modelID] = entry
        notify()
    }

    /// 记录一次请求活动，用于空闲计时。
    public func recordActivity(modelID: String) {
        guard var entry = entries[modelID] else { return }
        entry.lastUsed = now()
        entries[modelID] = entry
    }

    /// 空闲卸载：只处理非常驻、无租约、已就绪的模型。
    public func reapIdle(now referenceDate: Date? = nil) async {
        let current = referenceDate ?? now()
        let candidates = entries.values
            .filter { entry in
                guard entry.state.isReady, !entry.isResident, entry.activeLeases == 0 else { return false }
                guard let minutes = entry.config?.idleUnloadMinutes, minutes > 0 else { return false }
                return current.timeIntervalSince(entry.lastUsed) >= Double(minutes) * 60
            }
            .map { $0.model.id }

        for modelID in candidates {
            await stop(modelID: modelID, reason: "idle")
        }
    }

    public func startIdleTimer(interval: TimeInterval = 30) {
        idleTimer?.cancel()
        idleTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                if Task.isCancelled { return }
                await self?.reapIdle()
            }
        }
    }

    public func stop(modelID: String, reason: String = "manual") async {
        guard var entry = entries[modelID] else { return }
        entry.intentionalStop = true
        entry.startTask?.cancel()
        entry.startTask = nil

        if case .stopped = entry.state, entry.process == nil {
            entry.intentionalStop = false
            entries[modelID] = entry
            return
        }

        entry.state = .stopping
        entries[modelID] = entry
        notify()

        if let process = entry.process {
            process.terminate()
            let deadline = now().addingTimeInterval(shutdownGracePeriod)
            while process.isRunning && now() < deadline {
                try? await Task.sleep(for: .milliseconds(50))
            }
            if process.isRunning {
                process.forceKill()
            }
        }

        entry = entries[modelID] ?? entry
        entry.process = nil
        entry.pid = nil
        entry.state = .stopped
        entry.intentionalStop = false
        entry.restartCount = 0
        entry.activeLeases = 0
        entries[modelID] = entry
        persistPIDRegistry()
        notify()
    }

    /// 用当前配置重启进程（服务参数修改后生效）。
    public func restart(modelID: String) async throws -> URL {
        guard let entry = entries[modelID] else { throw RuntimeError.modelStopped }
        let model = entry.model
        let config = entry.config ?? ServerLaunchConfig()
        await stop(modelID: modelID, reason: "restart")
        return try await ensure(model: model, config: config)
    }

    public func shutdown() async {
        idleTimer?.cancel()
        idleTimer = nil
        let modelIDs = Array(entries.keys)
        for modelID in modelIDs {
            await stop(modelID: modelID, reason: "shutdown")
        }
    }

    // MARK: - Private

    private func checkMemory(for model: ModelRef) throws {
        guard memoryCheckEnabled else { return }
        let required = memoryEstimator(model.directory)
        guard required > 0 else { return }
        let available = memory.availableMemoryBytes()
        guard required <= available else {
            throw RuntimeError.insufficientMemory(requiredBytes: required, availableBytes: available)
        }
    }

    private func bootstrap(model: ModelRef, config: ServerLaunchConfig) async throws -> URL {
        do {
            try checkMemory(for: model)
            let pythonExecutable = try await python.ensureInstalled()
            let port = try portAllocator()
            guard let baseURL = URL(string: "http://127.0.0.1:\(port)") else {
                throw RuntimeError.portUnavailable
            }
            let logURL = paths.logURL(forModel: model.name)
            let arguments = ServerArguments.make(modelDirectory: model.directory, port: port, options: config.options)
            let process = try launcher.launch(
                executable: pythonExecutable,
                arguments: arguments,
                environment: [:],
                logURL: logURL
            )

            var entry = entries[model.id] ?? Entry(model: model, lastUsed: now())
            entry.process = process
            entry.pid = process.pid
            entry.startedAt = now()
            entry.state = .starting
            entry.config = config
            entries[model.id] = entry
            persistPIDRegistry()
            notify()

            let pid = process.pid
            process.onExit { [weak self] code in
                Task { await self?.handleExit(modelID: model.id, pid: pid, code: code) }
            }

            let deadline = now().addingTimeInterval(readinessTimeout)
            while true {
                if Task.isCancelled { throw RuntimeError.cancelled }
                if !process.isRunning {
                    throw RuntimeError.launchFailed(reason: "进程已退出，请查看日志：\(logURL.path)")
                }
                if await health.isServerReady(baseURL: baseURL, timeout: max(1, readinessPollInterval * 4)) {
                    let identifier = await health.firstModelIdentifier(baseURL: baseURL)
                    var readyEntry = entries[model.id] ?? entry
                    readyEntry.state = .ready(baseURL)
                    readyEntry.serverModelID = identifier ?? model.directory.path
                    readyEntry.startTask = nil
                    readyEntry.lastUsed = now()
                    entries[model.id] = readyEntry
                    persistPIDRegistry()
                    notify()
                    return baseURL
                }
                if now() >= deadline {
                    throw RuntimeError.readinessTimedOut(seconds: readinessTimeout)
                }
                try await Task.sleep(for: .milliseconds(max(10, Int(readinessPollInterval * 1000))))
            }
        } catch {
            if let process = entries[model.id]?.process {
                entries[model.id]?.process = nil
                entries[model.id]?.pid = nil
                process.terminate()
            }
            var failedEntry = entries[model.id] ?? Entry(model: model, lastUsed: now())
            failedEntry.startTask = nil
            if error is CancellationError {
                failedEntry.state = .stopped
                failedEntry.intentionalStop = false
            } else {
                failedEntry.state = .failed(error.localizedDescription)
            }
            entries[model.id] = failedEntry
            persistPIDRegistry()
            notify()
            throw error
        }
    }

    private func handleExit(modelID: String, pid: Int32, code: Int32) async {
        guard var entry = entries[modelID], entry.pid == pid, !entry.intentionalStop else { return }
        entry.process = nil
        entry.pid = nil

        if case .ready = entry.state, let config = entry.config {
            if let lastRestart = entry.lastRestartAt, now().timeIntervalSince(lastRestart) > restartWindow {
                entry.restartCount = 0
            }
            if entry.restartCount < 1 {
                entry.restartCount += 1
                entry.lastRestartAt = now()
                entry.state = .starting
                entries[modelID] = entry
                notify()
                let model = entry.model
                let task = Task { try await self.bootstrap(model: model, config: config) }
                entry.startTask = task
                entries[modelID] = entry
                _ = try? await task.value
                return
            }
            entry.state = .failed("模型服务进程异常退出（退出码 \(code)）")
            entries[modelID] = entry
            persistPIDRegistry()
            notify()
            return
        }

        if case .starting = entry.state {
            entry.state = .failed("模型服务进程异常退出（退出码 \(code)）")
        }
        entries[modelID] = entry
        persistPIDRegistry()
        notify()
    }

    private func persistPIDRegistry() {
        let records = entries.values.compactMap { entry -> PIDRegistry.Record? in
            guard let pid = entry.pid, entry.process != nil else { return nil }
            return PIDRegistry.Record(modelID: entry.model.id, pid: pid, startedAt: entry.startedAt ?? now())
        }
        PIDRegistry(fileURL: paths.pidRegistryFile).write(records)
    }

    private func notify() {
        snapshotObserver?(snapshot())
    }
}
