import AVFoundation
import Foundation

public enum AudioBufferTools {
    /// 深拷贝，供实时回调把音频安全地交给异步消费者。
    public static func copy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else {
            return nil
        }
        copy.frameLength = buffer.frameLength
        let source = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        let destination = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        guard source.count == destination.count else { return nil }
        for index in 0..<source.count {
            guard let sourceData = source[index].mData, let destinationData = destination[index].mData else {
                continue
            }
            memcpy(destinationData, sourceData, Int(source[index].mDataByteSize))
        }
        return copy
    }

    /// 生成一段指定频率、采样率的单声道测试音，用于单元测试。
    public static func makeSineBuffer(
        frequency: Double,
        sampleRate: Double,
        seconds: Double,
        format: AVAudioFormat? = nil
    ) -> AVAudioPCMBuffer? {
        guard let format = format ?? AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            return nil
        }
        let frameCount = AVAudioFrameCount(sampleRate * seconds)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount
        guard let channel = buffer.floatChannelData?[0] else { return nil }
        for frame in 0..<Int(frameCount) {
            channel[frame] = Float(sin(2 * .pi * frequency * Double(frame) / sampleRate)) * 0.2
        }
        return buffer
    }
}

public enum AudioConversionError: Error, LocalizedError {
    case unsupportedFormat
    case converterFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat: return "不支持的音频格式。"
        case let .converterFailed(message): return "音频格式转换失败：\(message)"
        }
    }
}

/// 把采集格式转换成 SpeechAnalyzer 要求的格式。
public final class AudioFormatConverter {
    private let converter: AVAudioConverter
    public let inputFormat: AVAudioFormat
    public let outputFormat: AVAudioFormat

    public init?(from inputFormat: AVAudioFormat, to outputFormat: AVAudioFormat) {
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else { return nil }
        self.converter = converter
        self.inputFormat = inputFormat
        self.outputFormat = outputFormat
    }

    public func convert(_ input: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        let ratio = outputFormat.sampleRate / inputFormat.sampleRate
        let capacity = AVAudioFrameCount((Double(input.frameLength) * ratio).rounded(.up)) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: max(capacity, 64)) else {
            throw AudioConversionError.converterFailed("无法分配输出缓冲区")
        }

        var provided = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, outStatus in
            if provided {
                outStatus.pointee = .noDataNow
                return nil
            }
            provided = true
            outStatus.pointee = .haveData
            return input
        }

        if status == .error {
            throw AudioConversionError.converterFailed(conversionError?.localizedDescription ?? "未知错误")
        }
        return output
    }
}
