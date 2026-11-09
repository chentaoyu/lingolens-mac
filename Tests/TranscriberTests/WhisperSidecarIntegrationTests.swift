import AVFoundation
import Foundation
import Testing
@testable import AudioCapture
@testable import Transcriber

private struct SendableAudio: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
}

/// 真实拉起边车进程，验证协议与识别结果。默认跳过。
///
/// LINGOLENS_WHISPER_MODEL=<模型目录> \
/// LINGOLENS_WHISPER_PYTHON=<venv python> \
/// LINGOLENS_WHISPER_AUDIO=<音频文件> \
///   swift test --filter WhisperSidecarIntegrationTests
@Suite("Whisper 边车集成")
struct WhisperSidecarIntegrationTests {
    private static var environment: [String: String] { ProcessInfo.processInfo.environment }

    private static func scriptURL() -> URL? {
        // 仓库根目录下的 Resources/stt/lingolens_stt.py
        // Tests/TranscriberTests/<file> → 上溯三级到仓库根目录
        var directory = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 {
            directory.deleteLastPathComponent()
        }
        let candidate = directory.appendingPathComponent("Resources/stt/lingolens_stt.py")
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }

    @Test(
        "喂音频得到定稿文本",
        .enabled(if: environment["LINGOLENS_WHISPER_MODEL"] != nil
            && environment["LINGOLENS_WHISPER_PYTHON"] != nil
            && environment["LINGOLENS_WHISPER_AUDIO"] != nil),
        .timeLimit(.minutes(5))
    )
    func transcribesAudio() async throws {
        let environment = Self.environment
        let model = URL(fileURLWithPath: try #require(environment["LINGOLENS_WHISPER_MODEL"]))
        let python = URL(fileURLWithPath: try #require(environment["LINGOLENS_WHISPER_PYTHON"]))
        let audioPath = try #require(environment["LINGOLENS_WHISPER_AUDIO"])
        let script = try #require(Self.scriptURL())

        // 按 100 ms 切块，模拟真实采集节奏。
        let file = try AVAudioFile(forReading: URL(fileURLWithPath: audioPath))
        let source = try #require(AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(file.length)
        ))
        try file.read(into: source)

        let chunkSize = max(1, Int(file.processingFormat.sampleRate * 0.1))
        var chunks: [SendableAudio] = []
        var offset = 0
        while offset < Int(source.frameLength) {
            let count = min(chunkSize, Int(source.frameLength) - offset)
            guard let part = AVAudioPCMBuffer(
                pcmFormat: source.format,
                frameCapacity: AVAudioFrameCount(count)
            ) else { break }
            part.frameLength = AVAudioFrameCount(count)
            for channel in 0..<Int(source.format.channelCount) {
                if let src = source.floatChannelData?[channel],
                   let dst = part.floatChannelData?[channel] {
                    dst.update(from: src + offset, count: count)
                }
            }
            chunks.append(SendableAudio(buffer: part))
            offset += count
        }

        let transcriber = WhisperTranscriber(
            modelDirectory: model,
            pythonExecutable: python,
            scriptURL: script,
            language: "zh",
            hotwords: ["ES", "API", "latency", "PRD", "deadline", "feature", "release", "beta", "standup"]
        )
        let events = try await transcriber.start()

        let collector = Task { () -> [String] in
            var texts: [String] = []
            for await event in events {
                switch event {
                case .ready:
                    break
                case let .final(segment):
                    texts.append(segment.text)
                    print("[whisper] \(String(format: "%.1f-%.1f", segment.start, segment.end))s \(segment.text)")
                case let .failure(message):
                    print("[whisper] 失败：\(message)")
                }
            }
            return texts
        }

        for chunk in chunks {
            await transcriber.append(chunk.buffer)
            try? await Task.sleep(for: .milliseconds(4))
        }
        await transcriber.finish()

        let texts = await collector.value
        let joined = texts.joined()
        print("[whisper] 合计 \(texts.count) 段：\(joined)")

        #expect(!texts.isEmpty)
        // 英文缩写是中英文模型的关键差别，这里专门断言。
        #expect(joined.contains("ES"))
        #expect(joined.contains("API"))
    }
}
