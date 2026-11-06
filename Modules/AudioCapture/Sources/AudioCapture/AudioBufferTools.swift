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

    /// 缓冲区电平（RMS，映射到 0…1）：-60 dB 视为静音，0 dB 视为满刻度。
    /// 只用于界面上的音量指示，不参与转写。
    public static func level(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channels = buffer.floatChannelData else { return 0 }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }
        let channelCount = max(1, Int(buffer.format.channelCount))

        var sum: Float = 0
        for channel in 0..<channelCount {
            let samples = channels[channel]
            for frame in 0..<frames {
                let value = samples[frame]
                sum += value * value
            }
        }

        let rms = sqrt(sum / Float(frames * channelCount))
        guard rms > 0 else { return 0 }
        let decibels = 20 * log10(rms)
        return max(0, min(1, (decibels + 60) / 60))
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
    /// 转换器没有报错却吐出全 0：多声道混音失败时 AVAudioConverter 会这样「静默失败」。
    case silentOutput

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat: return "不支持的音频格式。"
        case let .converterFailed(message): return "音频格式转换失败：\(message)"
        case .silentOutput: return "音频混音后没有任何声音，声道映射可能不受支持。"
        }
    }
}

/// 把采集格式转换成 SpeechAnalyzer 要求的格式。
public final class AudioFormatConverter {
    private let converter: AVAudioConverter
    /// 输入与目标声道数不同时，需要自己先把多声道混成目标声道数。
    private let needsChannelMixdown: Bool
    /// 混音后的中间格式：保持输入采样率，Float32 非交织，方便直接相加。
    private let mixdownFormat: AVAudioFormat
    public let inputFormat: AVAudioFormat
    public let outputFormat: AVAudioFormat

    public init?(from inputFormat: AVAudioFormat, to outputFormat: AVAudioFormat) {
        let needsChannelMixdown = inputFormat.channelCount != outputFormat.channelCount
        let mixdownFormat: AVAudioFormat
        if needsChannelMixdown {
            guard let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: inputFormat.sampleRate,
                channels: outputFormat.channelCount,
                interleaved: false
            ) else { return nil }
            mixdownFormat = format
        } else {
            mixdownFormat = inputFormat
        }

        guard let converter = AVAudioConverter(from: mixdownFormat, to: outputFormat) else { return nil }
        self.converter = converter
        self.mixdownFormat = mixdownFormat
        self.needsChannelMixdown = needsChannelMixdown
        self.inputFormat = inputFormat
        self.outputFormat = outputFormat
    }

    public func convert(_ input: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        let source = needsChannelMixdown ? try downmixed(input) : input

        let ratio = outputFormat.sampleRate / source.format.sampleRate
        let capacity = AVAudioFrameCount((Double(source.frameLength) * ratio).rounded(.up)) + 64
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
            return source
        }

        if status == .error {
            throw AudioConversionError.converterFailed(conversionError?.localizedDescription ?? "未知错误")
        }

        // 混音后仍然静音说明声道映射失败，宁可报错也不要继续喂静音给识别器。
        if needsChannelMixdown, Self.hasSignal(source), !Self.hasSignal(output) {
            throw AudioConversionError.silentOutput
        }
        return output
    }

    // MARK: - 多声道混音

    /// 多声道 → 目标声道数（逐声道求平均）。
    ///
    /// MacBook 的三麦克风阵列开启 voice processing 后，输入节点会变成 9 声道、布局标记为
    /// `DiscreteInOrder`。这种离散布局没有声道标签，交给 AVAudioConverter 直接降到单声道时
    /// 它会返回 `.haveData` 与正常帧数，但采样值全是 0——不报错、不丢帧，只是安静地变成静音。
    /// 于是识别器收不到任何声音，字幕一直停在「等待语音…」。这里自己混音，再把混好的
    /// 单声道交给转换器改采样率与位深。
    private func downmixed(_ input: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        let frames = Int(input.frameLength)
        let sourceChannels = Int(input.format.channelCount)
        let targetChannels = Int(mixdownFormat.channelCount)
        guard frames > 0, sourceChannels > 0, targetChannels > 0 else {
            throw AudioConversionError.unsupportedFormat
        }
        guard let output = AVAudioPCMBuffer(pcmFormat: mixdownFormat, frameCapacity: input.frameLength),
              let destination = output.floatChannelData
        else {
            throw AudioConversionError.converterFailed("无法分配混音缓冲区")
        }
        output.frameLength = input.frameLength

        var samples = [Float](repeating: 0, count: frames)
        guard Self.accumulate(input, into: &samples) else {
            throw AudioConversionError.unsupportedFormat
        }
        let scale = 1 / Float(sourceChannels)
        for frame in 0..<frames { samples[frame] *= scale }

        for channel in 0..<targetChannels {
            samples.withUnsafeBufferPointer { buffer in
                guard let base = buffer.baseAddress else { return }
                destination[channel].update(from: base, count: frames)
            }
        }
        return output
    }

    /// 把各声道累加进 `samples`（不除声道数，交给调用方缩放）。
    private static func accumulate(_ buffer: AVAudioPCMBuffer, into samples: inout [Float]) -> Bool {
        let frames = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        guard frames > 0, channels > 0 else { return true }

        let buffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        let interleaved = buffer.format.isInterleaved

        switch buffer.format.commonFormat {
        case .pcmFormatFloat32:
            if interleaved {
                guard let raw = buffers.first?.mData else { return false }
                let data = raw.assumingMemoryBound(to: Float.self)
                for frame in 0..<frames {
                    for channel in 0..<channels {
                        samples[frame] += data[frame * channels + channel]
                    }
                }
            } else {
                guard buffers.count >= channels else { return false }
                for channel in 0..<channels {
                    guard let raw = buffers[channel].mData else { return false }
                    let data = raw.assumingMemoryBound(to: Float.self)
                    for frame in 0..<frames { samples[frame] += data[frame] }
                }
            }
        case .pcmFormatInt16:
            let scale = 1 / Float(Int16.max)
            if interleaved {
                guard let raw = buffers.first?.mData else { return false }
                let data = raw.assumingMemoryBound(to: Int16.self)
                for frame in 0..<frames {
                    for channel in 0..<channels {
                        samples[frame] += Float(data[frame * channels + channel]) * scale
                    }
                }
            } else {
                guard buffers.count >= channels else { return false }
                for channel in 0..<channels {
                    guard let raw = buffers[channel].mData else { return false }
                    let data = raw.assumingMemoryBound(to: Int16.self)
                    for frame in 0..<frames { samples[frame] += Float(data[frame]) * scale }
                }
            }
        default:
            return false
        }
        return true
    }

    /// 判断缓冲区里有没有有效信号；判断不了时返回 true，避免误报静音。
    private static func hasSignal(_ buffer: AVAudioPCMBuffer) -> Bool {
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return false }
        var samples = [Float](repeating: 0, count: frames)
        guard accumulate(buffer, into: &samples) else { return true }
        return samples.contains { abs($0) > 0.0001 }
    }
}
