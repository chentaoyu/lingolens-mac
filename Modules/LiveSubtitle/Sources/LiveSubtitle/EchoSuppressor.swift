import AudioCapture
import Foundation

/// 回声去重：外放时对方的声音会从麦克风串进来（采集故意关掉了系统级回声消除，
/// 否则系统音频会被 duck 掉），于是同一句话会以「对方」和「我」两条出现。
///
/// 这里保留最近几秒「对方」的定稿文本，若「我」这条与它高度相似就丢弃。
public struct EchoSuppressor {
    /// 只在这个时间窗内比较（秒）。
    public static let window: TimeInterval = 6
    /// 字符二元组重合度达到该值即认为是同一句话。
    public static let threshold: Double = 0.5

    private struct Entry {
        let text: String
        let at: Date
    }

    private var recent: [Entry] = []

    public init() {}

    /// 记录一条「对方」的定稿，供后续比较。
    public mutating func noteOther(_ text: String, at date: Date = Date()) {
        recent.append(Entry(text: text, at: date))
        prune(now: date)
    }

    /// 判断这条「我」的文本是否只是对方的回声。
    public mutating func isEcho(_ text: String, at date: Date = Date()) -> Bool {
        prune(now: date)
        let normalized = Self.normalize(text)
        guard normalized.count >= 2 else { return false }
        for entry in recent where date.timeIntervalSince(entry.at) <= Self.window {
            if Self.similarity(normalized, Self.normalize(entry.text)) >= Self.threshold {
                return true
            }
        }
        return false
    }

    public mutating func reset() {
        recent.removeAll()
    }

    private mutating func prune(now: Date) {
        recent.removeAll { now.timeIntervalSince($0.at) > Self.window }
    }

    /// 只保留中日韩字符与字母数字，忽略标点和空格（两路识别的标点常不一样）。
    static func normalize(_ text: String) -> String {
        let kept = text.unicodeScalars.filter { scalar in
            CharacterSet.alphanumerics.contains(scalar) || (0x4E00...0x9FFF).contains(scalar.value)
        }
        return String(String.UnicodeScalarView(kept)).lowercased()
    }

    /// 字符二元组 Jaccard 相似度。
    static func similarity(_ lhs: String, _ rhs: String) -> Double {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        let a = bigrams(lhs)
        let b = bigrams(rhs)
        guard !a.isEmpty, !b.isEmpty else { return lhs == rhs ? 1 : 0 }
        let intersection = a.intersection(b).count
        let union = a.union(b).count
        return union == 0 ? 0 : Double(intersection) / Double(union)
    }

    private static func bigrams(_ text: String) -> Set<String> {
        let chars = Array(text)
        guard chars.count >= 2 else { return Set([text]) }
        var result = Set<String>()
        for index in 0..<(chars.count - 1) {
            result.insert(String(chars[index...(index + 1)]))
        }
        return result
    }
}
