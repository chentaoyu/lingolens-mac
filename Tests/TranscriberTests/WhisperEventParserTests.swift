import AVFoundation
import Foundation
import Testing
@testable import Transcriber

@Suite("转写边车协议解析")
struct WhisperEventParserTests {
    @Test("识别 ready")
    func parsesReady() {
        #expect(WhisperEventParser.parse(#"{"type": "ready"}"#) == .ready)
    }

    @Test("识别 final 及其时间")
    func parsesFinal() {
        let line = #"{"type": "final", "text": "用 ES 去查", "start": 1.5, "end": 3.25, "elapsed": 0.4}"#
        guard case let .final(segment)? = WhisperEventParser.parse(line) else {
            Issue.record("没有解析出 final")
            return
        }
        #expect(segment.text == "用 ES 去查")
        #expect(segment.start == 1.5)
        #expect(segment.end == 3.25)
    }

    @Test("识别 error")
    func parsesError() {
        let line = #"{"type": "error", "message": "RuntimeError: boom"}"#
        #expect(WhisperEventParser.parse(line) == .failure("RuntimeError: boom"))
    }

    @Test("空文本与非协议行被忽略")
    func ignoresNoise() {
        #expect(WhisperEventParser.parse(#"{"type": "final", "text": "   "}"#) == nil)
        #expect(WhisperEventParser.parse("") == nil)
        #expect(WhisperEventParser.parse("[stt] model loaded") == nil)
        #expect(WhisperEventParser.parse(#"{"type": "unknown"}"#) == nil)
        #expect(WhisperEventParser.parse("not json") == nil)
    }

    @Test("中文不会被转义破坏")
    func keepsChinese() {
        let line = #"{"type":"final","text":"明天的 standup 改到 10 点","start":0,"end":2}"#
        guard case let .final(segment)? = WhisperEventParser.parse(line) else {
            Issue.record("没有解析出 final")
            return
        }
        #expect(segment.text == "明天的 standup 改到 10 点")
    }
}

@Suite("PCM 编码")
struct PCM16EncoderTests {
    @Test("float32 转小端 int16")
    func encodesSamples() throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4))
        buffer.frameLength = 4
        let channel = try #require(buffer.floatChannelData?[0])
        channel[0] = 0
        channel[1] = 1.0
        channel[2] = -1.0
        channel[3] = 0.5

        let data = try #require(PCM16Encoder.encode(buffer))
        #expect(data.count == 8)

        let values = data.withUnsafeBytes { raw in
            Array(raw.bindMemory(to: Int16.self))
        }
        #expect(values[0] == 0)
        #expect(values[1] == 32767)
        #expect(values[2] == -32767)
        #expect(abs(Int(values[3]) - 16383) <= 1)
    }

    @Test("超范围样本会被钳制")
    func clampsOutOfRange() throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 2))
        buffer.frameLength = 2
        let channel = try #require(buffer.floatChannelData?[0])
        channel[0] = 4.0
        channel[1] = -4.0

        let data = try #require(PCM16Encoder.encode(buffer))
        let values = data.withUnsafeBytes { raw in Array(raw.bindMemory(to: Int16.self)) }
        #expect(values[0] == 32767)
        #expect(values[1] == -32767)
    }

    @Test("空缓冲区返回 nil")
    func emptyBuffer() throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8))
        buffer.frameLength = 0
        #expect(PCM16Encoder.encode(buffer) == nil)
    }
}
