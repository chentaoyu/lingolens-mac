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

    @Test("电平：正弦波落在 0…1 的可用区间")
    func levelOfSine() throws {
        let buffer = try #require(AudioBufferTools.makeSineBuffer(
            frequency: 440,
            sampleRate: 48_000,
            seconds: 0.1
        ))
        // 幅度 0.2 → RMS ≈ 0.141，约 -17 dB，落在 0.7 附近。
        let level = AudioBufferTools.level(of: buffer)
        #expect(level > 0.6)
        #expect(level < 0.8)
    }

    @Test("电平：静音为 0")
    func levelOfSilence() throws {
        let buffer = try #require(AudioBufferTools.makeSineBuffer(
            frequency: 440,
            sampleRate: 48_000,
            seconds: 0.1
        ))
        let samples = try #require(buffer.floatChannelData?[0])
        for index in 0..<Int(buffer.frameLength) {
            samples[index] = 0
        }
        #expect(AudioBufferTools.level(of: buffer) == 0)
    }

    @Test("多声道离散布局（麦克风阵列）混音后仍有声音")
    func downmixesDiscreteLayout() throws {
        // MacBook 三麦克风阵列开启 voice processing 后输入节点是 9 声道、DiscreteInOrder 布局。
        // 这种布局直接交给 AVAudioConverter 会「成功」返回全 0 的采样值（帧数正确、不报错），
        // 识别器因此收不到任何声音，实时字幕一直停在「等待语音…」。
        let tag = AudioChannelLayoutTag(kAudioChannelLayoutTag_DiscreteInOrder | 9)
        let layout = try #require(AVAudioChannelLayout(layoutTag: tag))
        let inputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            interleaved: false,
            channelLayout: layout
        )
        let frames = AVAudioFrameCount(4_800)
        let input = try #require(AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: frames))
        input.frameLength = frames
        let channels = try #require(input.floatChannelData)
        for channel in 0..<9 {
            for frame in 0..<Int(frames) {
                channels[channel][frame] = Float(sin(2 * .pi * 440 * Double(frame) / 48_000)) * 0.2
            }
        }

        let outputFormat = try #require(AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: true
        ))
        let converter = try #require(AudioFormatConverter(from: inputFormat, to: outputFormat))
        let output = try converter.convert(input)
        let samples = try #require(output.int16ChannelData?[0])

        var sum = 0.0
        for frame in 0..<Int(output.frameLength) {
            let value = Double(samples[frame]) / 32_768
            sum += value * value
        }
        let rms = sqrt(sum / Double(output.frameLength))
        #expect(output.frameLength > 1_000)
        // 幅度 0.2 的正弦混音后 RMS 仍在 0.1 以上；出 bug 时这里是 0。
        #expect(rms > 0.1)
    }

    @Test("多声道静音混音后不报错")
    func downmixSilenceDoesNotThrow() throws {
        let tag = AudioChannelLayoutTag(kAudioChannelLayoutTag_DiscreteInOrder | 3)
        let layout = try #require(AVAudioChannelLayout(layoutTag: tag))
        let inputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            interleaved: false,
            channelLayout: layout
        )
        let input = try #require(AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: 1_024))
        input.frameLength = 1_024

        let outputFormat = try #require(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: true
        ))
        let converter = try #require(AudioFormatConverter(from: inputFormat, to: outputFormat))
        let output = try converter.convert(input)
        #expect(output.frameLength > 0)
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
