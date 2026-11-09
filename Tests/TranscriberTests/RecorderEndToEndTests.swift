import AVFoundation
import Foundation
import Testing
@testable import AudioCapture
@testable import Transcriber

private struct Box: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
}

/// 一次性验证：采集格式 → 录音落盘 → 回读 → 转写，确认整条链路可用。
@Suite("录音端到端验证")
struct RecorderEndToEndTests {
    @Test("录成 m4a 再回读仍能识别", .enabled(if: ProcessInfo.processInfo.environment["LINGOLENS_REC_E2E"] != nil))
    func recordThenTranscribe() async throws {
        let sourcePath = try #require(ProcessInfo.processInfo.environment["LINGOLENS_REC_E2E"])
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LingoE2E-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("audio-other.m4a")

        // 1. 按真实采集格式切块喂给录音器
        let file = try AVAudioFile(forReading: URL(fileURLWithPath: sourcePath))
        let recorder = try ChannelAudioRecorder(url: output)
        let chunkFrames: AVAudioFrameCount = 4_800  // 100 ms @ 48 kHz
        var fed: AVAudioFrameCount = 0
        while fed < AVAudioFrameCount(file.length) {
            let remaining = AVAudioFrameCount(file.length) - fed
            let count = min(chunkFrames, remaining)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: count) else { break }
            try file.read(into: buffer, frameCount: count)
            recorder.append(buffer)
            fed += count
        }
        recorder.finish()

        print("[e2e] 采集 \(Double(fed) / file.processingFormat.sampleRate)s → 写入 \(recorder.duration)s, 失败 \(recorder.failureCount)")

        // 2. 回读录音，确认格式与有声
        let recorded = try AVAudioFile(forReading: output)
        let recordedSeconds = Double(recorded.length) / recorded.fileFormat.sampleRate
        print("[e2e] 文件 \(recorded.fileFormat.sampleRate) Hz × \(recorded.fileFormat.channelCount) ch, \(recordedSeconds)s")
        #expect(recorded.fileFormat.sampleRate == 16_000)
        #expect(recorded.fileFormat.channelCount == 1)
        #expect(abs(recordedSeconds - Double(fed) / file.processingFormat.sampleRate) < 0.5)

        let pcm = try #require(AVAudioPCMBuffer(
            pcmFormat: recorded.processingFormat,
            frameCapacity: AVAudioFrameCount(recorded.length)
        ))
        try recorded.read(into: pcm)
        let level = AudioBufferTools.level(of: pcm)
        print("[e2e] 录音电平 \(level)")
        #expect(level > 0.01)

        // 3. 用回读的录音做一次转写，确认识别链路没被编码破坏
        var chunkBuffers: [Box] = []
        let size = max(1, Int(pcm.frameLength) / 300)
        var offset = 0
        while offset < Int(pcm.frameLength) {
            let count = min(size, Int(pcm.frameLength) - offset)
            guard let part = AVAudioPCMBuffer(pcmFormat: pcm.format, frameCapacity: AVAudioFrameCount(count)) else { break }
            part.frameLength = AVAudioFrameCount(count)
            for ch in 0..<Int(pcm.format.channelCount) {
                if let src = pcm.floatChannelData?[ch], let dst = part.floatChannelData?[ch] {
                    dst.update(from: src + offset, count: count)
                }
            }
            chunkBuffers.append(Box(buffer: part))
            offset += count
        }
        let session = SpeechTranscriptionSession(channel: .other)
        let events = try await session.start(localeIdentifiers: ["zh-Hans"])
        let collector = Task { () -> String in
            var text = ""
            for await event in events where event.isFinal { text += event.text }
            return text
        }
        for box in chunkBuffers {
            await session.append(box.buffer)
            try? await Task.sleep(for: .milliseconds(100))
        }
        try? await Task.sleep(for: .seconds(2))
        await session.finish()
        let text = await collector.value
        print("[e2e] 回读转写：\(text)")
        #expect(text.contains("ES") || text.contains("效率"))
    }
}
