import Foundation
import Testing
@testable import ModelRuntime

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ date: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        self.current = date
    }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func advance(_ seconds: TimeInterval) {
        lock.lock()
        current = current.addingTimeInterval(seconds)
        lock.unlock()
    }
}

private final class MockProcess: LaunchedProcess, @unchecked Sendable {
    let pid: Int32
    private let lock = NSLock()
    private var running = true
    private var handler: (@Sendable (Int32) -> Void)?
    private var exitCode: Int32 = 0
    private(set) var terminateCount = 0
    private(set) var forceKillCount = 0

    init(pid: Int32) {
        self.pid = pid
    }

    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return running
    }

    func onExit(_ handler: @escaping @Sendable (Int32) -> Void) {
        lock.lock()
        if !running {
            let code = exitCode
            lock.unlock()
            handler(code)
            return
        }
        self.handler = handler
        lock.unlock()
    }

    func terminate() {
        lock.lock()
        terminateCount += 1
        lock.unlock()
        finish(code: 0)
    }

    func forceKill() {
        lock.lock()
        forceKillCount += 1
        lock.unlock()
        finish(code: 9)
    }

    func crash(code: Int32 = 1) {
        finish(code: code)
    }

    private func finish(code: Int32) {
        lock.lock()
        guard running else {
            lock.unlock()
            return
        }
        running = false
        exitCode = code
        let callback = handler
        handler = nil
        lock.unlock()
        callback?(code)
    }
}

private final class MockLauncher: ProcessLaunching, @unchecked Sendable {
    private let lock = NSLock()
    private var processes: [MockProcess] = []
    private var recordedArguments: [String] = []
    private var nextPID: Int32 = 1000

    func launch(
        executable: URL,
        arguments: [String],
        environment: [String: String],
        logURL: URL
    ) throws -> any LaunchedProcess {
        lock.lock()
        defer { lock.unlock() }
        nextPID += 1
        let process = MockProcess(pid: nextPID)
        processes.append(process)
        recordedArguments = arguments
        return process
    }

    var launchedProcesses: [MockProcess] {
        lock.lock()
        defer { lock.unlock() }
        return processes
    }

    var lastArguments: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recordedArguments
    }
}

private actor MockHealth: HealthChecking {
    private let readyAfterCalls: Int
    private let identifier: String?
    private var calls = 0

    init(readyAfterCalls: Int = 1, identifier: String? = nil) {
        self.readyAfterCalls = readyAfterCalls
        self.identifier = identifier
    }

    func isServerReady(baseURL: URL, timeout: TimeInterval) async -> Bool {
        calls += 1
        return calls >= readyAfterCalls
    }

    func firstModelIdentifier(baseURL: URL) async -> String? {
        identifier
    }
}

private struct MockMemory: MemoryProbing {
    var available: UInt64

    func availableMemoryBytes() -> UInt64 { available }
}

private struct MockInstallerRunner: CommandRunning {
    let pythonExecutable: URL

    func run(
        executable: URL,
        arguments: [String],
        environment: [String: String]?,
        lineHandler: (@Sendable (String) -> Void)?
    ) async throws -> Int32 {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(
            at: pythonExecutable.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !fileManager.fileExists(atPath: pythonExecutable.path) {
            fileManager.createFile(
                atPath: pythonExecutable.path,
                contents: Data("#!/bin/sh\n".utf8),
                attributes: [.posixPermissions: 0o755]
            )
        }
        lineHandler?("mocked install")
        return 0
    }
}

private func makePaths() -> RuntimePaths {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("LingoLensTests-\(UUID().uuidString)", isDirectory: true)
    let paths = RuntimePaths(
        appSupportDirectory: root.appendingPathComponent("support", isDirectory: true),
        logsDirectory: root.appendingPathComponent("logs", isDirectory: true)
    )
    try? paths.prepare()
    return paths
}

private func makePython(_ paths: RuntimePaths) -> PythonEnvironment {
    PythonEnvironment(
        paths: paths,
        runner: MockInstallerRunner(pythonExecutable: paths.pythonExecutable),
        uvLocator: { URL(fileURLWithPath: "/usr/bin/true") }
    )
}

private func makePool(
    paths: RuntimePaths,
    launcher: MockLauncher,
    health: MockHealth,
    memory: MockMemory = MockMemory(available: 64 * 1024 * 1024 * 1024),
    clock: TestClock = TestClock(),
    estimator: @escaping @Sendable (URL) -> UInt64 = { _ in 0 },
    port: Int = 43210
) -> ServerPool {
    ServerPool(
        paths: paths,
        python: makePython(paths),
        launcher: launcher,
        health: health,
        memory: memory,
        portAllocator: { port },
        now: { clock.now },
        memoryEstimator: estimator,
        readinessTimeout: 2,
        readinessPollInterval: 0.01,
        shutdownGracePeriod: 0.2,
        memoryCheckEnabled: true,
        cleanupStaleProcesses: false
    )
}

private func makeModel(_ name: String = "Qwen3.5-4B-MLX-4bit") -> ModelRef {
    ModelRef(id: name, name: name, directory: URL(fileURLWithPath: "/tmp/models/\(name)", isDirectory: true))
}

private func waitUntil(
    timeout: TimeInterval = 3,
    _ condition: @Sendable () async -> Bool
) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return await condition()
}

@Suite("ServerPool 状态机")
struct ServerPoolTests {
    @Test("启动后进入 ready 并复用同一个进程")
    func startsAndReuses() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.appSupportDirectory.deletingLastPathComponent()) }
        let launcher = MockLauncher()
        let pool = makePool(paths: paths, launcher: launcher, health: MockHealth())
        let model = makeModel()

        let url = try await pool.ensure(model: model, config: ServerLaunchConfig())
        #expect(url.absoluteString == "http://127.0.0.1:43210")
        #expect(launcher.launchedProcesses.count == 1)
        #expect(launcher.lastArguments.contains("mlx_vlm.server"))
        #expect(launcher.lastArguments.contains("--port"))

        _ = try await pool.ensure(model: model, config: ServerLaunchConfig())
        #expect(launcher.launchedProcesses.count == 1)

        let state = await pool.state(for: model.id)
        #expect(state == .ready(url))
    }

    @Test("非常驻模型空闲后会被 SIGTERM")
    func idleUnloads() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.appSupportDirectory.deletingLastPathComponent()) }
        let launcher = MockLauncher()
        let clock = TestClock()
        let pool = makePool(paths: paths, launcher: launcher, health: MockHealth(), clock: clock)
        let model = makeModel()

        _ = try await pool.ensure(model: model, config: ServerLaunchConfig(isResident: false, idleUnloadMinutes: 10))
        await pool.reapIdle(now: clock.now.addingTimeInterval(60))
        #expect(launcher.launchedProcesses.first?.terminateCount == 0)

        await pool.reapIdle(now: clock.now.addingTimeInterval(11 * 60))
        #expect(launcher.launchedProcesses.first?.terminateCount == 1)
        let state = await pool.state(for: model.id)
        #expect(state == .stopped)
    }

    @Test("租约携带服务端 /v1/models 的模型标识")
    func leaseCarriesServerModelIdentifier() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.appSupportDirectory.deletingLastPathComponent()) }
        let launcher = MockLauncher()
        let pool = makePool(
            paths: paths,
            launcher: launcher,
            health: MockHealth(identifier: "server-model-id")
        )
        let model = makeModel()

        let lease = try await pool.acquire(model: model, config: ServerLaunchConfig())
        #expect(lease.serverModelID == "server-model-id")
        #expect(lease.baseURL.absoluteString == "http://127.0.0.1:43210")
        await pool.release(lease)
    }

    @Test("租约未释放时不会被空闲卸载")
    func leasePreventsUnload() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.appSupportDirectory.deletingLastPathComponent()) }
        let launcher = MockLauncher()
        let clock = TestClock()
        let pool = makePool(paths: paths, launcher: launcher, health: MockHealth(), clock: clock)
        let model = makeModel()

        let lease = try await pool.acquire(model: model, config: ServerLaunchConfig(idleUnloadMinutes: 1))
        await pool.reapIdle(now: clock.now.addingTimeInterval(3600))
        let stateWhileLeased = await pool.state(for: model.id)
        #expect(stateWhileLeased.isReady)

        await pool.release(lease)
        await pool.reapIdle(now: clock.now.addingTimeInterval(3600))
        let stateAfterRelease = await pool.state(for: model.id)
        #expect(stateAfterRelease == .stopped)
    }

    @Test("常驻模型不会被空闲卸载")
    func residentNeverUnloads() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.appSupportDirectory.deletingLastPathComponent()) }
        let launcher = MockLauncher()
        let clock = TestClock()
        let pool = makePool(paths: paths, launcher: launcher, health: MockHealth(), clock: clock)
        let model = makeModel()

        _ = try await pool.ensure(model: model, config: ServerLaunchConfig(isResident: true, idleUnloadMinutes: 1))
        await pool.reapIdle(now: clock.now.addingTimeInterval(24 * 3600))
        let state = await pool.state(for: model.id)
        #expect(state.isReady)
        #expect(launcher.launchedProcesses.first?.terminateCount == 0)
    }

    @Test("崩溃后自动重启一次，再次崩溃进入失败状态")
    func crashRestartsOnce() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.appSupportDirectory.deletingLastPathComponent()) }
        let launcher = MockLauncher()
        let pool = makePool(paths: paths, launcher: launcher, health: MockHealth())
        let model = makeModel()

        _ = try await pool.ensure(model: model, config: ServerLaunchConfig(isResident: true))
        launcher.launchedProcesses[0].crash()

        let restarted = await waitUntil {
            guard launcher.launchedProcesses.count == 2 else { return false }
            let state = await pool.state(for: model.id)
            return state.isReady
        }
        #expect(restarted)

        launcher.launchedProcesses[1].crash()
        let failed = await waitUntil {
            let state = await pool.state(for: model.id)
            if case .failed = state { return true }
            return false
        }
        #expect(failed)
    }

    @Test("内存不足时拒绝启动")
    func rejectsOnLowMemory() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.appSupportDirectory.deletingLastPathComponent()) }
        let launcher = MockLauncher()
        let pool = makePool(
            paths: paths,
            launcher: launcher,
            health: MockHealth(),
            memory: MockMemory(available: 1024 * 1024 * 1024),
            estimator: { _ in 8 * 1024 * 1024 * 1024 }
        )
        let model = makeModel()

        await #expect(throws: RuntimeError.self) {
            _ = try await pool.ensure(model: model, config: ServerLaunchConfig())
        }
        #expect(launcher.launchedProcesses.isEmpty)
    }

    @Test("就绪超时会终止进程并记录失败")
    func readinessTimeout() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.appSupportDirectory.deletingLastPathComponent()) }
        let launcher = MockLauncher()
        let pool = ServerPool(
            paths: paths,
            python: makePython(paths),
            launcher: launcher,
            health: MockHealth(readyAfterCalls: .max),
            memory: MockMemory(available: UInt64.max / 2),
            portAllocator: { 43211 },
            readinessTimeout: 0.15,
            readinessPollInterval: 0.01,
            shutdownGracePeriod: 0.1,
            memoryCheckEnabled: false,
            cleanupStaleProcesses: false
        )
        let model = makeModel()

        await #expect(throws: RuntimeError.self) {
            _ = try await pool.ensure(model: model, config: ServerLaunchConfig())
        }
        #expect(launcher.launchedProcesses.first?.isRunning == false)
        let state = await pool.state(for: model.id)
        if case .failed = state {
            // ok
        } else {
            Issue.record("期望 failed，实际 \(state)")
        }
    }

    @Test("shutdown 停止所有进程")
    func shutdownStopsAll() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.appSupportDirectory.deletingLastPathComponent()) }
        let launcher = MockLauncher()
        let pool = makePool(paths: paths, launcher: launcher, health: MockHealth())

        _ = try await pool.ensure(model: makeModel("A"), config: ServerLaunchConfig())
        _ = try await pool.ensure(model: makeModel("B"), config: ServerLaunchConfig())
        #expect(launcher.launchedProcesses.count == 2)

        await pool.shutdown()
        let snapshot = await pool.snapshot()
        #expect(snapshot.allSatisfy { $0.state == .stopped })
        #expect(launcher.launchedProcesses.allSatisfy { $0.terminateCount == 1 })
    }

    @Test("关机后拒绝启动新进程")
    func rejectsEnsureAfterShutdown() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.appSupportDirectory.deletingLastPathComponent()) }
        let launcher = MockLauncher()
        let pool = makePool(paths: paths, launcher: launcher, health: MockHealth())

        await pool.shutdown()
        await #expect(throws: CancellationError.self) {
            _ = try await pool.ensure(model: makeModel(), config: ServerLaunchConfig())
        }
        #expect(launcher.launchedProcesses.isEmpty)
    }

    @Test("启动过程中关机：已拉起的进程会被终止")
    func shutdownDuringStartup() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.appSupportDirectory.deletingLastPathComponent()) }
        let launcher = MockLauncher()
        let pool = ServerPool(
            paths: paths,
            python: makePython(paths),
            launcher: launcher,
            health: MockHealth(readyAfterCalls: .max),
            memory: MockMemory(available: UInt64.max / 2),
            portAllocator: { 43212 },
            readinessTimeout: 5,
            readinessPollInterval: 0.01,
            shutdownGracePeriod: 0.1,
            memoryCheckEnabled: false,
            cleanupStaleProcesses: false
        )
        let model = makeModel()
        let task = Task { try await pool.ensure(model: model, config: ServerLaunchConfig()) }
        _ = await waitUntil { launcher.launchedProcesses.count == 1 }

        await pool.shutdown()
        _ = try? await task.value

        #expect(launcher.launchedProcesses.allSatisfy { !$0.isRunning })
        let state = await pool.state(for: model.id)
        #expect(state == .stopped)
    }
}
