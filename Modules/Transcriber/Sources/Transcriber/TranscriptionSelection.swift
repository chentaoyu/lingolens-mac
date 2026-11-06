import Foundation

/// 某一种语言对一段音频的识别候选。
public struct TranscriptionCandidate: Sendable, Equatable {
    public let language: String
    public let text: String
    public let isFinal: Bool
    /// final 结果才有；partial 为 0。
    public let confidence: Double
    public let rangeStart: Double
    public let rangeEnd: Double

    public init(
        language: String,
        text: String,
        isFinal: Bool,
        confidence: Double,
        rangeStart: Double,
        rangeEnd: Double
    ) {
        self.language = language
        self.text = text
        self.isFinal = isFinal
        self.confidence = confidence
        self.rangeStart = rangeStart
        self.rangeEnd = rangeEnd
    }
}

/// 多语言识别时判断「这句更像哪种语言」。
///
/// 每个 final 带一个置信度：说中文时中文模型约 0.95+，英文模型会硬凑出拼音式结果、只有 0.2 左右；
/// 反之英文时英文模型 0.95+，中文模型会凑出 0.65 左右的怪句子。所以用「当前语言最近的平均置信度」
/// 做门槛，只有明显更好的候选才切换语言，避免两种语言的结果交替上屏。
public struct TranscriptionLanguageTracker {
    /// 高置信度直接采信，不必再等另一种语言。
    public static let strongConfidence = 0.85
    /// 切换语言的最低置信度。
    public static let switchFloor = 0.45
    /// 同一句话的时间起点容差（秒）。
    public static let sameUtteranceWindow = 0.6

    public private(set) var activeLanguage: String?
    /// 每种语言最近一条 final 的置信度；用它当切换门槛，避免被更早的噪声结果稀释。
    private var lastConfidence: [String: Double] = [:]
    private var lastEmittedStart: Double?

    public init(initialLanguage: String? = nil) {
        activeLanguage = initialLanguage
    }

    /// 实时草稿只显示当前语言的那一份。
    public func acceptsPartial(_ language: String) -> Bool {
        language == activeLanguage
    }

    /// 返回 true 表示这条 final 应该上屏，同时更新当前语言。
    public mutating func acceptFinal(_ candidate: TranscriptionCandidate) -> Bool {
        lastConfidence[candidate.language] = candidate.confidence

        if candidate.language == activeLanguage {
            lastEmittedStart = candidate.rangeStart
            return true
        }

        if let active = activeLanguage {
            let activeScore = lastConfidence[active] ?? 0
            let threshold = max(Self.switchFloor, activeScore - 0.05)
            guard candidate.confidence >= threshold else { return false }
        }

        activeLanguage = candidate.language
        // 同一句已经用另一种语言上屏过，这次只切语言、不再重复一行。
        if let last = lastEmittedStart,
           abs(candidate.rangeStart - last) < Self.sameUtteranceWindow {
            return false
        }
        lastEmittedStart = candidate.rangeStart
        return true
    }
}

/// 记录每种语言「还在说、没出 final」的那句话从哪儿开始。
///
/// 中英混说时英文模型常在句中就吐出一段低置信度 final，而中文模型要等整句说完才定稿。
/// 只靠固定计时器会先把英文硬凑的结果放上屏；只要另一种语言这句还没定稿，就继续等它。
public struct OpenUtteranceTracker {
    /// 最长等待，避免另一种语言一直不出 final 时字幕卡住。
    public static let maxHold: TimeInterval = 8

    private var openStart: [String: Double] = [:]

    public init() {}

    public mutating func note(_ candidate: TranscriptionCandidate) {
        if candidate.isFinal {
            openStart[candidate.language] = nil
        } else if openStart[candidate.language] == nil {
            openStart[candidate.language] = candidate.rangeStart
        }
    }

    /// 另一种语言有一句与 held 重叠、还没定稿，就继续压着 held。
    public func shouldKeepHolding(_ held: TranscriptionCandidate, heldFor: TimeInterval) -> Bool {
        guard heldFor < Self.maxHold else { return false }
        return openStart.contains { $0.key != held.language && $0.value < held.rangeEnd }
    }
}
