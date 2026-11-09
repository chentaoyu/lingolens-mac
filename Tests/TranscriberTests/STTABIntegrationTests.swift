import AVFoundation
import Foundation
import Testing
@testable import Transcriber

/// AVAudioPCMBuffer 不是 Sendable；样本只在同一任务内顺序读取，用包装类型跨隔离域传递。
private struct SendableBuffer: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
}

/// 同一段音频喂给指定语言配置，打印识别结果供人工比对。
///
/// 用于验证「中英混说 + 英文缩写」的实际表现（例如 "ES" 被识别成 "淹死"）：
/// ```
/// LINGOLENS_STT_AB_FILE=/tmp/mixed.wav LINGOLENS_STT_AB_LOCALES=zh-Hans,en \
///   swift test --filter STTABIntegrationTests
/// ```
@Suite("转写 A/B 对照")
struct STTABIntegrationTests {
    /// 按约 100ms 一块切分，模拟真实采集节奏（一次性灌入会影响分句）。
    private static func samples(of path: String) throws -> [SendableBuffer] {
        let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
        let source = try #require(AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(file.length)
        ))
        try file.read(into: source)

        let size = max(1, Int(source.frameLength) / 300)
        var buffers: [SendableBuffer] = []
        var offset = 0
        while offset < Int(source.frameLength) {
            let count = min(size, Int(source.frameLength) - offset)
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
            buffers.append(SendableBuffer(buffer: part))
            offset += count
        }
        return buffers
    }

    @Test(
        "打印识别结果供人工比对",
        .enabled(if: ProcessInfo.processInfo.environment["LINGOLENS_STT_AB_FILE"] != nil)
    )
    func transcribesWithVariants() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["LINGOLENS_STT_AB_FILE"])
        let locales = (ProcessInfo.processInfo.environment["LINGOLENS_STT_AB_LOCALES"] ?? "zh-Hans")
            .split(separator: ",").map(String.init)
        let samples = try Self.samples(of: path)
        let session = SpeechTranscriptionSession(channel: .other)
        let events = try await session.start(localeIdentifiers: locales)

        let collector = Task { () -> [String] in
            var finals: [String] = []
            for await event in events where event.isFinal {
                finals.append("\(event.language ?? "?"): \(event.text)")
            }
            return finals
        }

        for sample in samples {
            await session.append(sample.buffer)
            try? await Task.sleep(for: .milliseconds(100))
        }
        try? await Task.sleep(for: .seconds(2))
        await session.finish()

        let finals = await collector.value
        print("=== locales=\(locales) ===")
        for line in finals { print(line) }

        #expect(!finals.isEmpty)
    }
}
