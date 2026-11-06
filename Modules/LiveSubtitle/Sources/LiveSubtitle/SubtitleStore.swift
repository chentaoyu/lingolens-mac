import AudioCapture
import Foundation
import Transcriber

/// 字幕行状态；partial 会原地更新，final 触发翻译。
@MainActor
public final class SubtitleStore: ObservableObject {
    @Published public private(set) var lines: [SubtitleLine] = []
    public var maxLines: Int

    private var partialIDs: [AudioChannel: UUID] = [:]

    public init(maxLines: Int = 8) {
        self.maxLines = maxLines
    }

    /// 接收转写事件。返回 final 行 id（partial 返回 nil）。
    @discardableResult
    public func apply(_ event: TranscriptionEvent) -> UUID? {
        let text = event.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if !event.isFinal {
            if let id = partialIDs[event.channel], let index = lines.firstIndex(where: { $0.id == id }) {
                lines[index].text = text
            } else {
                let line = SubtitleLine(channel: event.channel, text: text, isFinal: false)
                lines.append(line)
                partialIDs[event.channel] = line.id
                trim()
            }
            return nil
        }

        let id: UUID
        if let partialID = partialIDs[event.channel],
           let index = lines.firstIndex(where: { $0.id == partialID }) {
            lines[index].text = text
            lines[index].isFinal = true
            id = partialID
        } else {
            let line = SubtitleLine(channel: event.channel, text: text, isFinal: true)
            lines.append(line)
            id = line.id
        }
        partialIDs[event.channel] = nil
        trim()
        return id
    }

    public func setTranslation(lineID: UUID, text: String) {
        guard let index = lines.firstIndex(where: { $0.id == lineID }) else { return }
        lines[index].translation = text.trimmingCharacters(in: .whitespacesAndNewlines)
        lines[index].failed = false
    }

    public func markFailed(lineID: UUID) {
        guard let index = lines.firstIndex(where: { $0.id == lineID }) else { return }
        lines[index].failed = true
    }

    public func clear() {
        lines.removeAll()
        partialIDs.removeAll()
    }

    private func trim() {
        guard lines.count > maxLines else { return }
        let removed = lines.prefix(lines.count - maxLines)
        let removedIDs = Set(removed.map(\.id))
        lines.removeFirst(lines.count - maxLines)
        for (channel, id) in partialIDs where removedIDs.contains(id) {
            partialIDs[channel] = nil
        }
    }
}
