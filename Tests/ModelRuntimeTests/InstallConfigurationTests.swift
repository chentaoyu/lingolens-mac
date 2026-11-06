import Foundation
import Testing
@testable import ModelRuntime

/// 记录调用参数、可配置失败的 runner。
final class RecordingRunner: CommandRunning, @unchecked Sendable {
    struct Call: Sendable {
        let arguments: [String]
        let environment: [String: String]?
    }

    private let mutex = NSLock()
    private var recorded: [Call] = []
    private var remainingInstallFailures: Int

    init(failingInstallAttempts: Int = 0) {
        self.remainingInstallFailures = failingInstallAttempts
    }

    var calls: [Call] {
        mutex.lock(); defer { mutex.unlock() }
        return recorded
    }

    var installCalls: [Call] {
        calls.filter { $0.arguments.first == "pip" }
    }

    /// 非 async 上下文里加锁，避免 NSLock 在异步上下文中不可用。
    private func record(arguments: [String], environment: [String: String]?) -> Bool {
        mutex.lock()
        defer { mutex.unlock() }
        recorded.append(Call(arguments: arguments, environment: environment))
        if arguments.first == "pip", remainingInstallFailures > 0 {
            remainingInstallFailures -= 1
            return true
        }
        return false
    }

    func run(
        executable: URL,
        arguments: [String],
        environment: [String: String]?,
        lineHandler: (@Sendable (String) -> Void)?
    ) async throws -> Int32 {
        let shouldFail = record(arguments: arguments, environment: environment)

        if arguments.first == "venv", arguments.count > 1 {
            let venv = URL(fileURLWithPath: arguments[1])
            let python = venv.appendingPathComponent("bin/python3")
            try? FileManager.default.createDirectory(at: python.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: python.path) {
                FileManager.default.createFile(atPath: python.path, contents: Data(), attributes: [.posixPermissions: 0o755])
            }
        }

        if shouldFail {
            lineHandler?("error: Request failed after 5 retries in 61s")
            lineHandler?("  cause: tls handshake eof")
            return 1
        }
        return 0
    }
}

private func temporaryPaths() -> RuntimePaths {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("LingoInstall-\(UUID().uuidString)", isDirectory: true)
    let paths = RuntimePaths(
        appSupportDirectory: root.appendingPathComponent("support", isDirectory: true),
        logsDirectory: root.appendingPathComponent("logs", isDirectory: true)
    )
    try? paths.prepare()
    return paths
}

@Suite("安装下载源配置")
struct InstallConfigurationTests {
    @Test("自动模式优先国内镜像并回退官方源")
    func automaticAttempts() {
        let configuration = InstallConfiguration(source: .automatic)
        let hosts = configuration.indexAttempts.map { $0?.host }
        #expect(hosts == ["mirrors.aliyun.com", "pypi.org"])
    }

    @Test("明确选择官方源时不再回退")
    func officialOnly() {
        let configuration = InstallConfiguration(source: .official)
        #expect(configuration.indexAttempts.count == 1)
        #expect(configuration.indexAttempts.first??.host == "pypi.org")
    }

    @Test("自定义源非法时回退官方源")
    func invalidCustom() {
        let configuration = InstallConfiguration(source: .custom, customIndexURL: "not a url")
        #expect(configuration.indexAttempts.first??.absoluteString == InstallConfiguration.officialIndexURL.absoluteString)
    }

    @Test("自定义源有效时排在官方源之前")
    func customAttempts() {
        let configuration = InstallConfiguration(source: .custom, customIndexURL: "https://pypi.example.com/simple/")
        let hosts = configuration.indexAttempts.map { $0?.host }
        #expect(hosts == ["pypi.example.com", "pypi.org"])
    }

    @Test("uv 环境变量包含超时、重试与代理")
    func environment() {
        let configuration = InstallConfiguration(source: .automatic, proxyURL: "http://127.0.0.1:7890")
        let env = configuration.uvEnvironment
        #expect(env["UV_HTTP_TIMEOUT"] == "60")
        #expect(env["UV_HTTP_RETRIES"] == "5")
        #expect(env["HTTPS_PROXY"] == "http://127.0.0.1:7890")
        #expect(env["http_proxy"] == "http://127.0.0.1:7890")
    }

    @Test("没有代理时不写代理变量")
    func noProxy() {
        let env = InstallConfiguration(source: .automatic).uvEnvironment
        #expect(env["HTTPS_PROXY"] == nil)
        #expect(env["ALL_PROXY"] == nil)
    }
}

@Suite("uv 输出解析")
struct InstallOutputParserTests {
    /// 真实抓取的 uv 输出片段。
    static let sample = [
        "Using Python 3.12.13 environment at: /tmp/x/venv",
        "Resolved 73 packages in 1.33s",
        "Downloading mlx-vlm (3.5MiB)",
        "Downloading pygments (1.2MiB)",
        "Downloading mlx-metal (74.5MiB)",
        " Downloaded pygments",
        "Downloading scipy (19.5MiB)",
        " Downloaded scipy",
        "Prepared 73 packages in 2.1s",
        "Installed 73 packages in 412ms",
        " + uvicorn==0.54.0",
        " + websockets==17.4"
    ]

    @Test("解析包总数、下载进度与体积")
    func parsesProgress() {
        var parser = InstallOutputParser()
        for line in Self.sample.prefix(8) {
            parser.consume(line)
        }
        let activity = parser.activity
        #expect(activity.totalPackages == 73)
        #expect(activity.startedPackages == 4)
        #expect(activity.downloadedPackages == 2)
        #expect(activity.currentPackage == "scipy")
        let expectedKnown = Int(3.5 * 1024 * 1024) + Int(1.2 * 1024 * 1024) + Int(74.5 * 1024 * 1024) + Int(19.5 * 1024 * 1024)
        #expect(activity.knownBytes == expectedKnown)
        #expect(activity.downloadedBytes == Int(1.2 * 1024 * 1024) + Int(19.5 * 1024 * 1024))
    }

    @Test("安装完成行会补齐包数量")
    func parsesInstallCompletion() {
        var parser = InstallOutputParser()
        for line in Self.sample {
            parser.consume(line)
        }
        #expect(parser.didFinish)
        #expect(parser.activity.installedPackages == 73)
    }

    @Test("错误行会被识别")
    func parsesErrors() {
        var parser = InstallOutputParser()
        parser.consume("error: Request failed after 5 retries in 61s")
        #expect(parser.didFail)
    }

    @Test("体积单位解析")
    func parsesSizes() {
        #expect(InstallOutputParser.byteCount(from: "74.5MiB") == 78_118_912)
        #expect(InstallOutputParser.byteCount(from: "1.2GiB") == 1_288_490_188)
        #expect(InstallOutputParser.byteCount(from: "512KiB") == 524_288)
        #expect(InstallOutputParser.byteCount(from: "3B") == 3)
        #expect(InstallOutputParser.byteCount(from: "bogus") == nil)
    }
}

@Suite("安装命令与回退")
struct InstallCommandTests {
    @Test("默认使用镜像源，并把网络参数传给 uv")
    func passesMirrorAndEnvironment() async throws {
        let paths = temporaryPaths()
        defer { try? FileManager.default.removeItem(at: paths.appSupportDirectory.deletingLastPathComponent()) }
        let runner = RecordingRunner()
        let environment = PythonEnvironment(
            paths: paths,
            runner: runner,
            configuration: InstallConfiguration(source: .automatic),
            uvLocator: { URL(fileURLWithPath: "/usr/bin/true") }
        )

        _ = try await environment.ensureInstalled()

        let install = try #require(runner.installCalls.first)
        #expect(install.arguments.contains("--index-url"))
        #expect(install.arguments.contains("https://mirrors.aliyun.com/pypi/simple/"))
        #expect(install.arguments.contains("mlx-vlm==0.7.12"))
        #expect(install.environment?["UV_HTTP_TIMEOUT"] == "60")
        #expect(install.environment?["UV_CACHE_DIR"] == paths.uvCacheDirectory.path)
        #expect(install.environment?["UV_PYTHON_INSTALL_DIR"] == paths.pythonInstallDirectory.path)
    }

    @Test("镜像源失败时自动回退官方源")
    func fallsBackToOfficial() async throws {
        let paths = temporaryPaths()
        defer { try? FileManager.default.removeItem(at: paths.appSupportDirectory.deletingLastPathComponent()) }
        let runner = RecordingRunner(failingInstallAttempts: 1)
        let environment = PythonEnvironment(
            paths: paths,
            runner: runner,
            configuration: InstallConfiguration(source: .automatic),
            uvLocator: { URL(fileURLWithPath: "/usr/bin/true") }
        )

        _ = try await environment.ensureInstalled()

        let installs = runner.installCalls
        #expect(installs.count == 2)
        #expect(installs[0].arguments.contains("https://mirrors.aliyun.com/pypi/simple/"))
        #expect(installs[1].arguments.contains("https://pypi.org/simple/"))
        #expect(await environment.isInstalled())
    }

    @Test("首次安装失败后再次安装会重试并成功")
    func retriesAfterFailure() async throws {
        let paths = temporaryPaths()
        defer { try? FileManager.default.removeItem(at: paths.appSupportDirectory.deletingLastPathComponent()) }
        // 两个源都失败 → 本次安装失败。
        let failing = RecordingRunner(failingInstallAttempts: 2)
        let first = PythonEnvironment(
            paths: paths,
            runner: failing,
            configuration: InstallConfiguration(source: .automatic),
            uvLocator: { URL(fileURLWithPath: "/usr/bin/true") }
        )
        await #expect(throws: RuntimeError.self) {
            _ = try await first.ensureInstalled()
        }
        #expect(!(await first.isInstalled()))

        // 网络恢复后再装（等价于 App 更新后重启触发的自动安装）。
        let runner = RecordingRunner()
        let second = PythonEnvironment(
            paths: paths,
            runner: runner,
            configuration: InstallConfiguration(source: .automatic),
            uvLocator: { URL(fileURLWithPath: "/usr/bin/true") }
        )
        _ = try await second.ensureInstalled()
        #expect(await second.isInstalled())
        #expect(runner.installCalls.count == 1)
    }

    @Test("已安装且版本未变时不再执行命令")
    func skipsWhenInstalled() async throws {
        let paths = temporaryPaths()
        defer { try? FileManager.default.removeItem(at: paths.appSupportDirectory.deletingLastPathComponent()) }
        let runner = RecordingRunner()
        let environment = PythonEnvironment(
            paths: paths,
            runner: runner,
            uvLocator: { URL(fileURLWithPath: "/usr/bin/true") }
        )
        _ = try await environment.ensureInstalled()
        let count = runner.calls.count
        _ = try await environment.ensureInstalled()
        #expect(runner.calls.count == count)
    }
}
