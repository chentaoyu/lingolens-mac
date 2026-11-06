import Foundation

public enum MeetingSegmenter {
    /// 粗略 token 估算：CJK 每字约 1 token，其他字符约 4 字符 1 token。
    public static func estimatedTokens(_ text: String) -> Int {
        var cjk = 0
        var other = 0
        for scalar in text.unicodeScalars {
            if scalar.value >= 0x2E80 {
                cjk += 1
            } else {
                other += 1
            }
        }
        if cjk == 0 {
            return max(1, other / 4)
        }
        return cjk + other / 4
    }

    public static func transcriptTokenCount(_ entries: [TranscriptEntry]) -> Int {
        entries.reduce(0) { $0 + estimatedTokens($1.text) + 8 }
    }

    public static func needsSegmentation(_ entries: [TranscriptEntry], contextLength: Int) -> Bool {
        transcriptTokenCount(entries) > max(1024, contextLength / 2)
    }

    /// 按预算把转写切成若干段，保持时间顺序。
    public static func segments(_ entries: [TranscriptEntry], tokenBudget: Int) -> [[TranscriptEntry]] {
        guard !entries.isEmpty else { return [] }
        let budget = max(256, tokenBudget)
        var result: [[TranscriptEntry]] = []
        var current: [TranscriptEntry] = []
        var currentTokens = 0

        for entry in entries {
            let tokens = estimatedTokens(entry.text) + 8
            if !current.isEmpty, currentTokens + tokens > budget {
                result.append(current)
                current = []
                currentTokens = 0
            }
            current.append(entry)
            currentTokens += tokens
        }
        if !current.isEmpty {
            result.append(current)
        }
        return result
    }
}
