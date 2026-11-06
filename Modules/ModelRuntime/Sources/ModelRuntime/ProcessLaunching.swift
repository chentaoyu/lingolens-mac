import Foundation

/// 已启动的子进程。
public protocol LaunchedProcess: AnyObject, Sendable {
    var pid: Int32 { get }
    var isRunning: Bool { get }
    func onExit(_ handler: @escaping @Sendable (Int32) -> Void)
    func terminate()
    func forceKill()
}

public protocol ProcessLaunching: Sendable {
    func launch(
        executable: URL,
        arguments: [String],
        environment: [String: String],
        logURL: URL
    ) throws -> any LaunchedProcess
}

public final class SystemLaunchedProcess: LaunchedProcess, @unchecked Sendable {
    private let process: Process
    private let lock = NSLock()
    private var handler: (@Sendable (Int32) -> Void)?
    private var deliveredExitCode: Int32?

    public init(process: Process) {
        self.process = process
        process.terminationHandler = { [weak self] finished in
            self?.deliver(finished.terminationStatus)
        }
    }

    public var pid: Int32 { process.processIdentifier }

    public var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return deliveredExitCode == nil && process.isRunning
    }

    public func onExit(_ handler: @escaping @Sendable (Int32) -> Void) {
        lock.lock()
        if let code = deliveredExitCode {
            lock.unlock()
            handler(code)
            return
        }
        self.handler = handler
        lock.unlock()
    }

    public func terminate() {
        guard process.isRunning else { return }
        process.terminate()
    }

    public func forceKill() {
        guard process.isRunning else { return }
        kill(process.processIdentifier, SIGKILL)
    }

    private func deliver(_ code: Int32) {
        lock.lock()
        guard deliveredExitCode == nil else {
            lock.unlock()
            return
        }
        deliveredExitCode = code
        let callback = handler
        handler = nil
        lock.unlock()
        callback?(code)
    }
}

public struct SystemProcessLauncher: ProcessLaunching {
    public init() {}

    public func launch(
        executable: URL,
        arguments: [String],
        environment: [String: String],
        logURL: URL
    ) throws -> any LaunchedProcess {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fileManager.fileExists(atPath: logURL.path) {
            fileManager.createFile(atPath: logURL.path, contents: nil)
        }

        let handle = try FileHandle(forWritingTo: logURL)
        handle.seekToEndOfFile()

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        process.standardOutput = handle
        process.standardError = handle
        process.standardInput = FileHandle.nullDevice
        try process.run()
        return SystemLaunchedProcess(process: process)
    }
}
