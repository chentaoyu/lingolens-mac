import AudioCapture
import Foundation

/// 会议目录：`<root>/<日期-时间>/meta.json、transcript.jsonl、minutes.md`。
public actor MeetingStore {
    private let root: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let idFormatter: DateFormatter

    public init(root: URL) {
        self.root = root

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        self.idFormatter = formatter
    }

    public func ensureRoot() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    @discardableResult
    public func create(title: String? = nil, languages: [AudioChannel: String], startedAt: Date = Date()) throws -> MeetingMeta {
        try ensureRoot()
        var identifier = idFormatter.string(from: startedAt)
        var suffix = 1
        while FileManager.default.fileExists(atPath: root.appendingPathComponent(identifier).path) {
            identifier = "\(idFormatter.string(from: startedAt))-\(suffix)"
            suffix += 1
        }

        let meta = MeetingMeta(
            id: identifier,
            title: title ?? defaultTitle(for: startedAt),
            startedAt: startedAt,
            languages: Dictionary(uniqueKeysWithValues: languages.map { ($0.key.rawValue, $0.value) })
        )
        try writeMeta(meta)
        let transcript = directory(for: identifier).appendingPathComponent("transcript.jsonl")
        FileManager.default.createFile(atPath: transcript.path, contents: nil)
        return meta
    }

    public func finish(id: String, endedAt: Date = Date()) throws {
        var meta = try loadMeta(id: id)
        meta.endedAt = endedAt
        try writeMeta(meta)
    }

    public func append(_ entry: TranscriptEntry, to id: String) throws {
        let url = directory(for: id).appendingPathComponent("transcript.jsonl")
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let data = try encoder.encode(entry)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        try handle.write(contentsOf: Data("\n".utf8))
    }

    public func loadMeta(id: String) throws -> MeetingMeta {
        let url = directory(for: id).appendingPathComponent("meta.json")
        guard let data = try? Data(contentsOf: url) else {
            throw MeetingError.meetingNotFound(id)
        }
        return try decoder.decode(MeetingMeta.self, from: data)
    }

    public func entries(id: String) throws -> [TranscriptEntry] {
        let url = directory(for: id).appendingPathComponent("transcript.jsonl")
        guard let data = try? Data(contentsOf: url) else { return [] }
        let lines = data.split(separator: 0x0A, omittingEmptySubsequences: true)
        var entries: [TranscriptEntry] = []
        for line in lines {
            if let entry = try? decoder.decode(TranscriptEntry.self, from: Data(line)) {
                entries.append(entry)
            }
        }
        return entries
    }

    /// 录音文件落在会议目录下，文件名形如 `audio-other.m4a`。
    public func audioFileURL(id: String, channel: AudioChannel) -> URL {
        directory(for: id).appendingPathComponent("audio-\(channel.rawValue).m4a")
    }

    /// 记录哪些通道已经落盘，供界面显示与后续重转写使用。
    public func setAudioFiles(id: String, files: [AudioChannel: URL]) throws {
        var meta = try loadMeta(id: id)
        meta.audioFiles = files.reduce(into: [String: String]()) { result, pair in
            result[pair.key.rawValue] = pair.value.lastPathComponent
        }
        try writeMeta(meta)
    }

    public func load(id: String) throws -> MeetingDetail {
        let meta = try loadMeta(id: id)
        let entries = try entries(id: id)
        let minutesURL = directory(for: id).appendingPathComponent("minutes.md")
        let minutes = try? String(contentsOf: minutesURL, encoding: .utf8)
        return MeetingDetail(meta: meta, entries: entries, minutes: minutes)
    }

    public func list() throws -> [MeetingSummary] {
        try ensureRoot()
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var summaries: [MeetingSummary] = []
        for url in contents {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            let metaURL = url.appendingPathComponent("meta.json")
            guard let data = try? Data(contentsOf: metaURL),
                  let meta = try? decoder.decode(MeetingMeta.self, from: data)
            else { continue }
            let hasMinutes = FileManager.default.fileExists(atPath: url.appendingPathComponent("minutes.md").path)
            summaries.append(
                MeetingSummary(meta: meta, hasMinutes: hasMinutes, preview: previewText(id: meta.id))
            )
        }
        return summaries.sorted { $0.meta.startedAt > $1.meta.startedAt }
    }

    public func saveMinutes(_ markdown: String, for id: String) throws {
        let url = directory(for: id).appendingPathComponent("minutes.md")
        do {
            try markdown.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw MeetingError.writeFailed(error.localizedDescription)
        }
    }

    public func updateTitle(id: String, title: String) throws {
        var meta = try loadMeta(id: id)
        meta.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        try writeMeta(meta)
    }

    public func updateEntry(meetingID: String, entryID: UUID, text: String) throws {
        var all = try entries(id: meetingID)
        guard let index = all.firstIndex(where: { $0.id == entryID }) else { return }
        all[index].text = text
        try rewriteEntries(all, id: meetingID)
    }

    public func updateTranslation(meetingID: String, entryID: UUID, translation: String) throws {
        var all = try entries(id: meetingID)
        guard let index = all.firstIndex(where: { $0.id == entryID }) else { return }
        all[index].translation = translation
        try rewriteEntries(all, id: meetingID)
    }

    public func delete(id: String) throws {
        try FileManager.default.removeItem(at: directory(for: id))
    }

    // MARK: - Private

    /// 只读转写文件开头的一小段，取第一条作为列表预览，避免长会议整文件解析。
    private func previewText(id: String) -> String? {
        let url = directory(for: id).appendingPathComponent("transcript.jsonl")
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: 8_192)) ?? Data()
        guard let line = data.split(separator: 0x0A, omittingEmptySubsequences: true).first,
              let entry = try? decoder.decode(TranscriptEntry.self, from: Data(line))
        else { return nil }
        let text = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : String(text.prefix(90))
    }

    private func directory(for id: String) -> URL {
        root.appendingPathComponent(id, isDirectory: true)
    }

    private func writeMeta(_ meta: MeetingMeta) throws {
        let directory = directory(for: meta.id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            try encoder.encode(meta).write(to: directory.appendingPathComponent("meta.json"), options: .atomic)
        } catch {
            throw MeetingError.writeFailed(error.localizedDescription)
        }
    }

    private func rewriteEntries(_ entries: [TranscriptEntry], id: String) throws {
        let url = directory(for: id).appendingPathComponent("transcript.jsonl")
        var data = Data()
        for entry in entries {
            data.append(try encoder.encode(entry))
            data.append(0x0A)
        }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw MeetingError.writeFailed(error.localizedDescription)
        }
    }

    private func defaultTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日 HH:mm"
        formatter.locale = Locale(identifier: "zh_CN")
        return "会议 \(formatter.string(from: date))"
    }
}
