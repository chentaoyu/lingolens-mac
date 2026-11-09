import AVFoundation
import Foundation
import Testing
@testable import AudioCapture

@Suite("录音收尾")
struct ChannelAudioRecorderFinalizeTests {
    private func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("LingoRec-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// 真实采集是「很多小块持续写入」，不同于单块写入。
    /// 这里按 100ms 一块写 20 秒，模拟真实会话，再立刻回读。
    @Test("持续写入 20 秒后文件可读")
    func readableAfterManyChunks() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("audio-other.m4a")

        let recorder = try ChannelAudioRecorder(url: url)
        let source = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        let chunk = try #require(AudioBufferTools.makeSineBuffer(
            frequency: 440, sampleRate: 48_000, seconds: 0.1, format: source
        ))

        for _ in 0..<200 {
            recorder.append(chunk)
        }
        recorder.finish()

        print("[finalize] 写入 \(String(format: "%.1f", recorder.duration))s，失败 \(recorder.failureCount)")
        let file = try AVAudioFile(forReading: url)
        let seconds = Double(file.length) / file.fileFormat.sampleRate
        print("[finalize] 回读 \(String(format: "%.1f", seconds))s")
        #expect(seconds > 18)
    }
}
