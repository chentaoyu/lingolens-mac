import AVFoundation
import Foundation
import Testing
@testable import AudioCapture

@Suite("音频缓冲工具")
struct AudioBufferToolsTests {
    @Test("深拷贝保留帧数与采样率")
    func copiesBuffer() throws {
        let buffer = try #require(AudioBufferTools.makeSineBuffer(
            frequency: 440,
            sampleRate: 48_000,
            seconds: 0.1
        ))
        let copy = try #require(AudioBufferTools.copy(buffer))
        #expect(copy.frameLength == buffer.frameLength)
        #expect(copy.format.sampleRate == buffer.format.sampleRate)
        #expect(copy.floatChannelData?[0][0] == buffer.floatChannelData?[0][0])
    }

    @Test("采样率转换到 16kHz")
    func resamples() throws {
        let inputFormat = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let outputFormat = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let input = try #require(AudioBufferTools.makeSineBuffer(
            frequency: 440,
            sampleRate: 48_000,
            seconds: 0.5,
            format: inputFormat
        ))
        let converter = try #require(AudioFormatConverter(from: inputFormat, to: outputFormat))
        let output = try converter.convert(input)

        #expect(output.format.sampleRate == 16_000)
        // 16k/48k * 24000 = 8000，允许转换器保留少量余量。
        #expect(output.frameLength > 7_000)
        #expect(output.frameLength < 9_000)
    }
}

@Suite("采集控制")
struct AudioCaptureControllerTests {
    @Test("未选择任何来源时抛错")
    func rejectsEmptyOptions() {
        let controller = AudioCaptureController()
        #expect(throws: AudioCaptureError.self) {
            _ = try controller.start(options: AudioCaptureOptions(captureSystemAudio: false, captureMicrophone: false))
        }
    }
}
