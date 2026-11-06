import Foundation
import Testing
@testable import ModelRuntime

private struct NoopRunner: CommandRunning {
    var calls: CallCounter?
    func run(executable: URL, arguments: [String], environment: [String: String]?, lineHandler: (@Sendable (String) -> Void)?) async throws -> Int32 {
        calls?.increment()
        if arguments.first == "venv", arguments.count > 1 {
            let venv = URL(fileURLWithPath: arguments[1])
            let python = venv.appendingPathComponent("bin/python3")
            try? FileManager.default.createDirectory(at: python.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: python.path) {
                FileManager.default.createFile(atPath: python.path, contents: Data(), attributes: [.posixPermissions: 0o755])
            }
        }
        return 0
    }
}

private final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
    func increment() { lock.lock(); value += 1; lock.unlock() }
}

private func makePaths() -> RuntimePaths {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("LingoTests-\(UUID().uuidString)", isDirectory: true)
    let paths = RuntimePaths(
        appSupportDirectory: root.appendingPathComponent("support", isDirectory: true),
        logsDirectory: root.appendingPathComponent("logs", isDirectory: true)
    )
    try? paths.prepare()
    return paths
}

@Suite("Python 环境安装")
struct PythonEnvironmentTests {
    @Test("首次安装执行 uv venv 与 pip install，第二次直接复用")
    func installsOnce() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.appSupportDirectory.deletingLastPathComponent()) }
        let counter = CallCounter()
        let environment = PythonEnvironment(
            paths: paths,
            runner: NoopRunner(calls: counter),
            uvLocator: { URL(fileURLWithPath: "/usr/bin/true") }
        )

        let python = try await environment.ensureInstalled()
        #expect(python == paths.pythonExecutable)
        #expect(counter.count == 2)
        let installed = await environment.isInstalled()
        #expect(installed)

        _ = try await environment.ensureInstalled()
        #expect(counter.count == 2)
    }

    @Test("没有 uv 时抛出 uvNotFound")
    func missingUV() async {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.appSupportDirectory.deletingLastPathComponent()) }
        let environment = PythonEnvironment(
            paths: paths,
            runner: NoopRunner(calls: nil),
            uvLocator: { nil }
        )

        await #expect(throws: RuntimeError.self) {
            _ = try await environment.ensureInstalled()
        }
    }

    @Test("固定版本变化会触发重装")
    func reinstallOnVersionChange() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.appSupportDirectory.deletingLastPathComponent()) }
        let counter = CallCounter()
        let first = PythonEnvironment(
            paths: paths,
            spec: RuntimeSpec(pythonVersion: "3.12", mlxVLMVersion: "0.3.1"),
            runner: NoopRunner(calls: counter),
            uvLocator: { URL(fileURLWithPath: "/usr/bin/true") }
        )
        _ = try await first.ensureInstalled()
        #expect(counter.count == 2)

        let second = PythonEnvironment(
            paths: paths,
            spec: RuntimeSpec(pythonVersion: "3.12", mlxVLMVersion: "0.4.0"),
            runner: NoopRunner(calls: counter),
            uvLocator: { URL(fileURLWithPath: "/usr/bin/true") }
        )
        _ = try await second.ensureInstalled()
        #expect(counter.count == 4)
    }
}

@Suite("服务参数与辅助类型")
struct RuntimeHelperTests {
    @Test("服务参数拼装")
    func serverArguments() {
        let arguments = ServerArguments.make(
            modelDirectory: URL(fileURLWithPath: "/tmp/model"),
            port: 5000,
            options: ServerOptions(kvCacheBits: 8, maxKVCacheLength: 8192, extraArguments: ["--verbose"])
        )
        #expect(arguments.contains("-m"))
        #expect(arguments.contains("mlx_vlm.server"))
        #expect(arguments.contains("--model"))
        #expect(arguments.contains("/tmp/model"))
        #expect(arguments.contains("--port"))
        #expect(arguments.contains("5000"))
        #expect(arguments.contains("--kv-bits"))
        #expect(arguments.contains("8"))
        #expect(arguments.contains("--max-kv-size"))
        #expect(arguments.contains("--verbose"))
    }

    @Test("空闲端口可以分配并被释放")
    func freePort() throws {
        let port = try FreePortAllocator.allocate()
        #expect(port > 1024)
        #expect(port < 65536)
    }

    @Test("PID 文件读写与残留清理（不存在的进程）")
    func pidRegistry() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let registry = PIDRegistry(fileURL: directory.appendingPathComponent("servers.json"))

        registry.write([
            .init(modelID: "a", pid: 999_999, startedAt: Date())
        ])
        #expect(registry.read().count == 1)
        registry.terminateStale()
        #expect(registry.read().isEmpty)
    }

    @Test("权重内存估算包含开销")
    func memoryEstimate() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("model.safetensors")
        try Data(repeating: 0, count: 1024).write(to: file)

        let weights = ModelMemoryEstimator.weightsBytes(directory: directory)
        let estimate = ModelMemoryEstimator.estimatedMemoryBytes(directory: directory)
        #expect(weights == 1024)
        #expect(estimate > weights)
    }

    @Test("日志文件名会做安全处理")
    func sanitizedLogName() {
        let name = RuntimePaths.sanitizedFileComponent("org/model name:4bit")
        #expect(!name.contains("/"))
        #expect(!name.contains(":"))
        #expect(!name.isEmpty)
    }
}
