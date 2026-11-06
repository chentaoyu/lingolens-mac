import AppKit
import AudioCapture
import Meetings
import SelectionTranslate
import SwiftUI

struct MeetingsView: View {
    @EnvironmentObject private var environment: AppEnvironment

    @State private var meetings: [MeetingSummary] = []
    @State private var selectedID: String?
    @State private var detail: MeetingDetail?
    @State private var titleDraft = ""

    @State private var templates: [MinutesTemplate] = []
    @State private var selectedTemplateID: UUID?
    @State private var minutesText = ""
    @State private var phaseText = ""
    @State private var isGenerating = false
    @State private var generationTask: Task<Void, Never>?
    @State private var searchText = ""
    @State private var minutesLanguage = "zh-Hans"
    @State private var showTemplateManager = false
    @State private var meetingQuery = ""
    @State private var isEditingMinutes = false

    var body: some View {
        // 用固定宽度的 HStack 而非 HSplitView：后者会按子视图理想宽度撑开，
        // 把外层 NavigationSplitView 的侧边栏挤出窗口。
        HStack(spacing: 0) {
            sidebar
                .frame(width: 240)
            Divider()
            detailPane
                .frame(minWidth: 460, maxWidth: .infinity)
        }
        .task { await reload() }
        .onChange(of: selectedID) { _, newValue in
            generationTask?.cancel()
            isGenerating = false
            guard let newValue, newValue != detail?.meta.id else { return }
            Task { await loadDetail(id: newValue) }
        }
        .onDisappear {
            generationTask?.cancel()
        }
        .onChange(of: environment.focusMeetingID) { _, newValue in
            guard newValue != nil else { return }
            Task { await reload() }
        }
        .onChange(of: environment.meetingsRevision) { _, _ in
            Task { await reload() }
        }
        .onChange(of: showTemplateManager) { _, showing in
            if !showing {
                Task { await reload() }
            }
        }
        .sheet(isPresented: $showTemplateManager) {
            MinutesTemplateSheet()
                .environmentObject(environment)
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("会议")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    Task { await reload() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("刷新")
                .accessibilityLabel("刷新会议列表")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            TextField("搜索会议", text: $meetingQuery)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 10)
                .padding(.bottom, 8)

            Divider()

            if meetings.isEmpty {
                ContentUnavailableView(
                    "还没有会议记录",
                    systemImage: "waveform",
                    description: Text("在菜单栏开始音频会话并打开“记录会议”，结束后会出现在这里。")
                )
            } else {
                List(selection: $selectedID) {
                    ForEach(filteredMeetings) { summary in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(summary.meta.title)
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(1)
                                if summary.hasMinutes {
                                    TagBadge(text: "纪要", color: .accentColor)
                                }
                            }
                            Text("\(dateString(summary.meta.startedAt)) · \(durationString(summary.meta.duration))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .tag(summary.meta.id)
                        .contextMenu {
                            Button("删除", role: .destructive) {
                                Task {
                                    await environment.deleteMeeting(id: summary.meta.id)
                                    if selectedID == summary.meta.id { selectedID = nil }
                                    await reload()
                                }
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if let detail {
            VStack(alignment: .leading, spacing: 12) {
                meetingHeader(detail)
                VSplitView {
                    transcriptSection(detail)
                        .padding(.bottom, 10)
                        .frame(minHeight: 160)
                    minutesSection(detail)
                        .padding(.top, 10)
                        .frame(minHeight: 220)
                }
            }
            .padding(16)
        } else {
            ContentUnavailableView(
                "选择一场会议",
                systemImage: "list.bullet.rectangle",
                description: Text("左侧选择会议查看转写与纪要。")
            )
        }
    }

    private func meetingHeader(_ detail: MeetingDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("会议标题", text: $titleDraft)
                .textFieldStyle(.plain)
                .font(.system(size: 18, weight: .semibold))
                .onSubmit {
                    Task {
                        await environment.renameMeeting(id: detail.meta.id, title: titleDraft)
                        await reload()
                    }
                }

            HStack(spacing: 12) {
                Label(dateString(detail.meta.startedAt), systemImage: "calendar")
                Label(durationString(detail.meta.duration), systemImage: "clock")
                Label("\(detail.entries.count) 句", systemImage: "text.bubble")
                if let ended = detail.meta.endedAt {
                    Label("结束于 \(timeString(ended))", systemImage: "flag.checkered")
                }
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func transcriptSection(_ detail: MeetingDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("转写")
                    .font(.system(size: 13, weight: .semibold))
                Text("回车保存单条修改")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                TextField("搜索转写", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 120, maxWidth: 200)
            }

            let visibleEntries = filteredEntries(detail)

            if visibleEntries.isEmpty {
                Text(detail.entries.isEmpty ? "这场会议没有转写内容。" : "没有匹配的转写。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(visibleEntries) { entry in
                            TranscriptRow(entry: entry) { text in
                                Task {
                                    await environment.updateTranscript(
                                        meetingID: detail.meta.id,
                                        entryID: entry.id,
                                        text: text
                                    )
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(minHeight: 120, maxHeight: .infinity)
            }
        }
    }

    private func minutesSection(_ detail: MeetingDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("会议纪要")
                    .font(.system(size: 13, weight: .semibold))

                Picker("模板", selection: $selectedTemplateID) {
                    ForEach(templates) { template in
                        Text(template.name).tag(Optional(template.id))
                    }
                }
                .labelsHidden()
                .frame(width: 140)

                Picker("输出语言", selection: $minutesLanguage) {
                    ForEach(TranslationPrompt.supportedTargetLanguages, id: \.id) { language in
                        Text(language.name).tag(language.id)
                    }
                }
                .labelsHidden()
                .frame(width: 100)

                Button("模板…") {
                    showTemplateManager = true
                }

                Spacer()

                if !minutesText.isEmpty && !isGenerating {
                    Picker("", selection: $isEditingMinutes) {
                        Text("预览").tag(false)
                        Text("编辑").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }
            .controlSize(.small)

            minutesBody(detail)

            HStack(spacing: 10) {
                if isGenerating {
                    ProgressView().controlSize(.small)
                }
                Text(phaseText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if isGenerating {
                    Button("停止") {
                        generationTask?.cancel()
                        isGenerating = false
                        phaseText = "已停止"
                    }
                } else if !minutesText.isEmpty {
                    Button("重新生成") { generate(for: detail) }
                        .disabled(templates.isEmpty || detail.entries.isEmpty)
                    if isEditingMinutes {
                        Button("保存") {
                            Task {
                                await environment.saveMinutes(minutesText, meetingID: detail.meta.id)
                                isEditingMinutes = false
                                phaseText = "已保存"
                                await reload()
                            }
                        }
                    }
                    Button("复制") {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(minutesText, forType: .string)
                        phaseText = "已复制 Markdown"
                    }
                    Button("导出 .md…") { exportMinutes(title: detail.meta.title) }
                        .buttonStyle(.borderedProminent)
                }
            }
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private func minutesBody(_ detail: MeetingDetail) -> some View {
        if minutesText.isEmpty && !isGenerating {
            VStack(spacing: 10) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 28))
                    .foregroundStyle(.tertiary)
                Text("还没有会议纪要")
                    .font(.system(size: 13, weight: .semibold))
                Text(detail.entries.isEmpty ? "这场会议没有转写内容，无法生成纪要。" : "将使用完整转写在本机生成结构化纪要。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("生成纪要") { generate(for: detail) }
                    .buttonStyle(.borderedProminent)
                    .disabled(templates.isEmpty || detail.entries.isEmpty)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        } else if isEditingMinutes && !isGenerating {
            TextEditor(text: $minutesText)
                .font(.system(size: 12, design: .monospaced))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.secondary.opacity(0.2))
                )
        } else {
            ScrollView {
                MarkdownPreview(text: minutesText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func exportMinutes(title: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = "\(title).md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try minutesText.write(to: url, atomically: true, encoding: .utf8)
            phaseText = "已导出到 \(url.lastPathComponent)"
        } catch {
            environment.lastError = "导出失败：\(error.localizedDescription)"
        }
    }

    private func generate(for detail: MeetingDetail) {
        guard let id = selectedTemplateID,
              let template = templates.first(where: { $0.id == id })
        else { return }

        isGenerating = true
        isEditingMinutes = false
        minutesText = ""
        phaseText = "准备生成…"

        generationTask = Task { @MainActor in
            do {
                let languageName = TranslationPrompt.languageName(minutesLanguage)
                for try await event in environment.minutesGenerator.generate(
                    meeting: detail,
                    template: template,
                    targetLanguage: languageName
                ) {
                    switch event {
                    case let .phase(text):
                        phaseText = text
                    case let .delta(text):
                        minutesText += text
                    case .finished:
                        break
                    }
                }
                await environment.saveMinutes(minutesText, meetingID: detail.meta.id)
                phaseText = "已生成并保存"
                isGenerating = false
                await reload()
            } catch is CancellationError {
                isGenerating = false
                phaseText = "已停止"
            } catch {
                isGenerating = false
                phaseText = "生成失败：\(error.localizedDescription)"
            }
        }
    }

    private func reload() async {
        meetings = await environment.loadMeetings()
        templates = await environment.templates()
        if selectedTemplateID == nil {
            selectedTemplateID = templates.first(where: { $0.id == MinutesTemplate.standardID })?.id
                ?? templates.first?.id
        }
        if let focus = environment.focusMeetingID {
            environment.focusMeetingID = nil
            selectedID = focus
        } else if selectedID == nil {
            selectedID = meetings.first?.id
        }
        if let selectedID {
            await loadDetail(id: selectedID)
        } else {
            detail = nil
        }
    }

    private func loadDetail(id: String) async {
        detail = await environment.loadMeeting(id: id)
        titleDraft = detail?.meta.title ?? ""
        minutesText = detail?.minutes ?? ""
        phaseText = ""
    }

    private var filteredMeetings: [MeetingSummary] {
        let query = meetingQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return meetings }
        return meetings.filter { $0.meta.title.localizedCaseInsensitiveContains(query) }
    }

    private func filteredEntries(_ detail: MeetingDetail) -> [TranscriptEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return detail.entries }
        return detail.entries.filter {
            $0.text.localizedCaseInsensitiveContains(query)
                || ($0.translation?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func durationString(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 {
            return "\(hours) 小时 \(minutes) 分"
        }
        return "\(minutes) 分"
    }
}

private struct TranscriptRow: View {
    let entry: TranscriptEntry
    let onSave: (String) -> Void

    @State private var text: String

    init(entry: TranscriptEntry, onSave: @escaping (String) -> Void) {
        self.entry = entry
        self.onSave = onSave
        _text = State(initialValue: entry.text)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(timeString)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .leading)

            Text(entry.speaker.displayName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(
                    Capsule().fill(entry.speaker.color.opacity(0.85))
                )

            VStack(alignment: .leading, spacing: 2) {
                TextField("", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .accessibilityLabel("\(entry.speaker.displayName)的发言")
                    .font(.system(size: 12))
                    .onSubmit { onSave(text) }

                if let translation = entry.translation, !translation.isEmpty {
                    Text(translation)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: entry.time)
    }
}
private struct MinutesTemplateSheet: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    @State private var templates: [MinutesTemplate] = []
    @State private var selectedID: UUID?
    @State private var name = ""
    @State private var prompt = ""
    @State private var isNew = false
    @State private var message = ""

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                List(selection: $selectedID) {
                    ForEach(templates) { template in
                        Text(template.name)
                            .tag(Optional(template.id))
                    }
                }
                .listStyle(.sidebar)

                HStack(spacing: 8) {
                    Button("新建") {
                        isNew = true
                        selectedID = nil
                        name = "新模板"
                        prompt = ""
                    }
                    Button("删除") {
                        deleteSelected()
                    }
                    .disabled(selectedID == nil || selectedID == MinutesTemplate.standardID)
                    Spacer()
                }
                .padding(8)
            }
            .frame(width: 200)

            VStack(alignment: .leading, spacing: 10) {
                TextField("模板名称", text: $name)
                    .textFieldStyle(.roundedBorder)

                Text("提示词（生成纪要时作为系统提示）")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextEditor(text: $prompt)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 240)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.secondary.opacity(0.2))
                    )

                HStack {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("取消") { dismiss() }
                    Button("保存") { save() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty
                            || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(12)
        }
        .frame(width: 720, height: 470)
        .task { await load() }
        .onChange(of: selectedID) { _, _ in loadSelection() }
    }

    private func load() async {
        templates = await environment.templates()
        isNew = false
        selectedID = templates.first(where: { $0.id == MinutesTemplate.standardID })?.id
            ?? templates.first?.id
        loadSelection()
    }

    private func loadSelection() {
        guard !isNew,
              let id = selectedID,
              let template = templates.first(where: { $0.id == id })
        else { return }
        name = template.name
        prompt = template.prompt
        message = ""
    }

    private func save() {
        Task {
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty, !trimmedPrompt.isEmpty else { return }

            if isNew {
                let template = await environment.addTemplate(name: trimmedName, prompt: trimmedPrompt)
                templates = await environment.templates()
                selectedID = template.id
                isNew = false
            } else if let id = selectedID,
                      var template = templates.first(where: { $0.id == id }) {
                template.name = trimmedName
                template.prompt = trimmedPrompt
                await environment.templateStore.update(template)
                templates = await environment.templates()
            }
            message = "已保存"
        }
    }

    private func deleteSelected() {
        guard let id = selectedID, id != MinutesTemplate.standardID else { return }
        Task {
            await environment.templateStore.delete(id: id)
            templates = await environment.templates()
            selectedID = templates.first?.id
            isNew = false
            loadSelection()
        }
    }
}

extension AudioChannel {
    /// 说话人配色，与字幕浮窗共用 Assets 中的颜色。
    var color: Color {
        switch self {
        case .me: return .speakerMe
        case .other: return .speakerOther
        }
    }
}

/// 纪要的轻量 Markdown 预览：标题、列表、任务项、表格与行内样式。
private struct MarkdownPreview: View {
    let text: String

    private enum Block {
        case line(String)
        case table([[String]])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case let .line(line): lineView(line)
                case let .table(rows): tableView(rows)
                }
            }
        }
        .textSelection(.enabled)
    }

    /// 连续的 `|` 行合并为一张表，跳过 `| --- |` 分隔行。
    private var blocks: [Block] {
        var result: [Block] = []
        var rows: [[String]] = []
        func flush() {
            if !rows.isEmpty { result.append(.table(rows)) }
            rows = []
        }
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("|") else {
                flush()
                result.append(.line(raw))
                continue
            }
            let cells = line
                .trimmingCharacters(in: CharacterSet(charactersIn: "|"))
                .components(separatedBy: "|")
                .map { $0.trimmingCharacters(in: .whitespaces) }
            if cells.allSatisfy({ $0.allSatisfy { "-: ".contains($0) } }) { continue }
            rows.append(cells)
        }
        flush()
        return result
    }

    private func tableView(_ rows: [[String]]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        inline(cell)
                            .font(.system(size: 12, weight: index == 0 ? .semibold : .regular))
                            .foregroundStyle(index == 0 ? .secondary : .primary)
                    }
                }
                if index == 0 {
                    Divider().gridCellUnsizedAxes(.horizontal)
                }
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private func lineView(_ raw: String) -> some View {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.isEmpty {
            Spacer().frame(height: 2)
        } else if let heading = strip(line, prefixes: ["### ", "## ", "# "]) {
            inline(heading.text)
                .font(.system(size: 18 - CGFloat(heading.level) * 2, weight: .semibold))
                .padding(.top, 6)
        } else if line.hasPrefix("- [ ] ") || line.hasPrefix("- [x] ") {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: line.hasPrefix("- [x] ") ? "checkmark.square" : "square")
                    .foregroundStyle(.secondary)
                inline(String(line.dropFirst(6)))
            }
            .font(.system(size: 13))
        } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("•").foregroundStyle(.secondary)
                inline(String(line.dropFirst(2)))
            }
            .font(.system(size: 13))
        } else {
            inline(line).font(.system(size: 13))
        }
    }

    private func strip(_ line: String, prefixes: [String]) -> (level: Int, text: String)? {
        for prefix in prefixes where line.hasPrefix(prefix) {
            return (prefix.count - 2, String(line.dropFirst(prefix.count)))
        }
        return nil
    }

    private func inline(_ text: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attributed)
        }
        return Text(text)
    }
}
