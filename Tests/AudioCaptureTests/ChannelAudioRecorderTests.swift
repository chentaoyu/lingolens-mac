import AVFoundation
import Foundation
import Testing
@testable import AudioCapture

@Suite("会议录音落盘")
struct ChannelAudioRecorderTests {
    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("LingoRecorder-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("把 48 kHz 立体声转成 16 kHz 单声道 m4a")
    func recordsConvertedAudio() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("audio-other.m4a")

        let recorder = try ChannelAudioRecorder(url: url)
        // 采集侧常见是 48 kHz 立体声，录音要自己降到 16 kHz 单声道。
        let source = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        let buffer = try #require(AudioBufferTools.makeSineBuffer(
            frequency: 440,
            sampleRate: 48_000,
            seconds: 1,
            format: source
        ))
        // 填充第二个声道，确保混音路径被覆盖。
        if let channels = buffer.floatChannelData {
            for frame in 0..<Int(buffer.frameLength) {
                channels[1][frame] = channels[0][frame]
            }
        }

        recorder.append(buffer)
        recorder.finish()

        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(recorder.failureCount == 0)
        // 1 秒 48k 音频转换后应接近 1 秒 16k 帧。
        #expect(recorder.duration > 0.9)
        #expect(recorder.duration < 1.1)

        let file = try AVAudioFile(forReading: url)
        #expect(file.fileFormat.sampleRate == ChannelAudioRecorder.sampleRate)
        #expect(file.fileFormat.channelCount == 1)
        let seconds = Double(file.length) / file.fileFormat.sampleRate
        #expect(seconds > 0.9)
        #expect(seconds < 1.1)
    }

    @Test("连续多块音频会累加到同一个文件")
    func appendsMultipleBuffers() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("audio-me.m4a")

        let recorder = try ChannelAudioRecorder(url: url)
        let buffer = try #require(AudioBufferTools.makeSineBuffer(
            frequency: 300,
            sampleRate: 16_000,
            seconds: 0.5
        ))
        for _ in 0..<4 {
            recorder.append(buffer)
        }
        recorder.finish()

        // 已经是 16k 单声道，应原样写入不多不少。
        #expect(recorder.writtenFrames == 32_000)

        let file = try AVAudioFile(forReading: url)
        let seconds = Double(file.length) / file.fileFormat.sampleRate
        #expect(seconds > 1.9)
        #expect(seconds < 2.1)
    }

    @Test("finish 之后的音频会被忽略")
    func ignoresAfterFinish() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let recorder = try ChannelAudioRecorder(url: directory.appendingPathComponent("a.m4a"))
        let buffer = try #require(AudioBufferTools.makeSineBuffer(
            frequency: 300,
            sampleRate: 16_000,
            seconds: 0.5
        ))
        recorder.append(buffer)
        recorder.finish()
        let framesAfterFinish = recorder.writtenFrames
        recorder.append(buffer)
        recorder.finish()
        #expect(recorder.writtenFrames == framesAfterFinish)
    }

    @Test("目录不存在时会自动创建")
    func createsDirectory() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let nested = directory.appendingPathComponent("nested/deeper/audio.m4a")
        let recorder = try ChannelAudioRecorder(url: nested)
        recorder.append(try #require(AudioBufferTools.makeSineBuffer(
            frequency: 300,
            sampleRate: 16_000,
            seconds: 0.2
        )))
        recorder.finish()
        #expect(FileManager.default.fileExists(atPath: nested.path))
    }
}
