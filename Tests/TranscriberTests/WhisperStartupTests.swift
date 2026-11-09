import AVFoundation
import Foundation
import Testing
@testable import Transcriber

/// 只验证「能启动并收到 ready」，不需要音频。默认跳过。
/// LINGOLENS_WHISPER_MODEL=<dir> LINGOLENS_WHISPER_PYTHON=<python> swift test --filter WhisperStartupTests
@Suite("Whisper 启动")
struct WhisperStartupTests {
    private static var environment: [String: String] { ProcessInfo.processInfo.environment }

    private static func scriptURL() -> URL? {
        var directory = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { directory.deleteLastPathComponent() }
        let candidate = directory.appendingPathComponent("Resources/stt/lingolens_stt.py")
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }

    private static func makeTranscriber() throws -> WhisperTranscriber {
        let environment = Self.environment
        let model = URL(fileURLWithPath: try #require(environment["LINGOLENS_WHISPER_MODEL"]))
        let python = URL(fileURLWithPath: try #require(environment["LINGOLENS_WHISPER_PYTHON"]))
        let script = try #require(Self.scriptURL())
        return WhisperTranscriber(
            modelDirectory: model,
            pythonExecutable: python,
            scriptURL: script,
            language: "zh"
        )
    }

    @Test(
        "启动后 15 秒内收到 ready",
        .enabled(if: environment["LINGOLENS_WHISPER_MODEL"] != nil
            && environment["LINGOLENS_WHISPER_PYTHON"] != nil),
        .timeLimit(.minutes(2))
    )
    func becomesReady() async throws {
        let transcriber = try Self.makeTranscriber()
        let began = Date()
        _ = try await transcriber.start()
        print("[startup] 单实例 ready 用时 \(String(format: "%.1f", Date().timeIntervalSince(began)))s")
        #expect(Date().timeIntervalSince(began) < 15)
        await transcriber.finish()
    }

    /// 两路音频会话会先后起两个边车；第二个曾经永远收不到 ready。
    @Test(
        "先后启动两个实例都能 ready",
        .enabled(if: environment["LINGOLENS_WHISPER_MODEL"] != nil
            && environment["LINGOLENS_WHISPER_PYTHON"] != nil),
        .timeLimit(.minutes(3))
    )
    func secondInstanceAlsoBecomesReady() async throws {
        let first = try Self.makeTranscriber()
        let second = try Self.makeTranscriber()

        let began = Date()
        _ = try await first.start()
        print("[startup] 第一个 ready 用时 \(String(format: "%.1f", Date().timeIntervalSince(began)))s")

        let secondStart = Date()
        _ = try await second.start()
        print("[startup] 第二个 ready 用时 \(String(format: "%.1f", Date().timeIntervalSince(secondStart)))s")

        #expect(Date().timeIntervalSince(secondStart) < 15)

        await second.finish()
        await first.finish()
    }
}
