import AVFoundation
import Foundation
import Testing
@testable import Transcriber

/// 需要 `LINGOLENS_SPEECH_TEST_FILE` 指向一段语音文件；默认跳过。
@Suite("语音转写集成")
struct SpeechTranscriptionIntegrationTests {
    @Test(
        "把音频文件转成文字",
        .enabled(if: ProcessInfo.processInfo.environment["LINGOLENS_SPEECH_TEST_FILE"] != nil)
    )
    func transcribeFile() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["LINGOLENS_SPEECH_TEST_FILE"])
        let locale = ProcessInfo.processInfo.environment["LINGOLENS_SPEECH_LOCALE"] ?? "zh-Hans"

        let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
        let buffer = try #require(AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(file.length)
        ))
        try file.read(into: buffer)

        let session = SpeechTranscriptionSession(channel: .other)
        let events = try await session.start(localeIdentifier: locale)

        let collector = Task { () -> [String] in
            var finals: [String] = []
            for await event in events where event.isFinal {
                finals.append(event.text)
            }
            return finals
        }

        await session.append(buffer)
        try? await Task.sleep(for: .seconds(2))
        await session.finish()

        let finals = await collector.value
        #expect(!finals.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}
