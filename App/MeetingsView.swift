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
    /// 转写栏占可分配宽度的比例；拖动分隔条时更新，跨会话保留。
    @AppStorage("meetings.splitRatio") private var transcriptRatio: Double = 0.53
    @State private var splitDragStart: Double?

    @State private var detailTab: DetailTab = .content
    @State private var highlightedEntryID: UUID?
    @State private var scrollTargetEntryID: UUID?
    @State private var showDeleteConfirm = false

    private enum DetailTab: String, CaseIterable, Identifiable {
        case content = "转写与纪要"
        case info = "会议信息"

        var id: Self { self }
    }

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
                // 空态只在这里留一行，完整引导放在右侧详情区，避免一屏三份说明。
                VStack(spacing: 6) {
                    Image(systemName: "waveform")
                        .font(.system(size: 20))
                        .foregroundStyle(.tertiary)
                    Text("暂无会议")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedID) {
                    ForEach(filteredMeetings) { summary in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(summary.meta.title)
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(1)
                                if summary.hasMinutes {
                                    TagBadge(text: "纪要", color: .accentColor)
                                }
                            }
                            Text("\(relativeDateString(summary.meta.startedAt)) · \(durationString(summary.meta.duration))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            if let preview = summary.preview, !preview.isEmpty {
                                Text(preview)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                        }
                        // 侧边栏列表行默认上下没有留白，多行内容会贴在一起；
                        // 给行内留出 8pt 呼吸空间（外加上下各 3pt 行距），选中高亮也跟着变高。
                        .padding(.vertical, 8)
                        .listRowInsets(EdgeInsets(top: 3, leading: 10, bottom: 3, trailing: 10))
                        .tag(summary.meta.id)
                        .contextMenu {
                            Button("在 Finder 中显示") {
                                revealMeeting(id: summary.meta.id)
                            }
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
                // 侧边栏列表默认铺一层灰色材质，和窗口底色叠在一起显得很重；
                // 关掉它，改由外层白底统一承担背景，标题与副标题的对比更清楚。
                .scrollContentBackground(.hidden)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    @ViewBuilder
    private var detailPane: some View {
        if let detail {
            VStack(alignment: .leading, spacing: 10) {
                meetingHeader(detail)

                Picker("", selection: $detailTab) {
                    ForEach(DetailTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()

                if detailTab == .content {
                    splitPanes(detail)
                } else {
                    meetingInfo(detail)
                }
            }
            .padding(16)
            .confirmationDialog(
                "删除这场会议？",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("删除", role: .destructive) { deleteMeeting(detail) }
                Button("取消", role: .cancel) {}
            } message: {
                Text("转写与纪要将一并删除，无法恢复。")
            }
        } else if meetings.isEmpty {
            ContentUnavailableView {
                Label("会议记录会保存在这里", systemImage: "waveform")
            } description: {
                Text("在菜单栏开始音频会话并打开「记录会议」，结束后的转写和纪要学会出现在这里。")
            } actions: {
                Button("开始音频会话") {
                    Task { await environment.startAudioSession() }
                }
                .buttonStyle(.borderedProminent)
            }
        } else {
            ContentUnavailableView(
                "选择一场会议",
                systemImage: "list.bullet.rectangle",
                description: Text("左侧选择会议查看转写与纪要。")
            )
        }
    }

    /// 转写 / 纪要左右分栏：默认按原型 53 / 47 分配，分隔条可拖动并记住比例。
    /// 外层宽度固定，两侧各自限制最小宽度，避免像 HSplitView 那样把窗口侧边栏挤出去。
    private func splitPanes(_ detail: MeetingDetail) -> some View {
        GeometryReader { proxy in
            let handleWidth: CGFloat = 10
            let usable = max(0, proxy.size.width - handleWidth)
            HStack(alignment: .top, spacing: 0) {
                transcriptSection(detail)
                    .frame(width: transcriptWidth(in: usable), alignment: .topLeading)
                    .frame(maxHeight: .infinity, alignment: .topLeading)

                splitHandle(usable: usable)

                minutesSection(detail)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    private let transcriptMinimumWidth: CGFloat = 220
    private let minutesMinimumWidth: CGFloat = 280

    /// 当前宽度下允许的转写占比区间；窗口过窄时返回 nil，退化为 50 / 50。
    private func allowedRatioRange(in usable: CGFloat) -> ClosedRange<Double>? {
        guard usable > transcriptMinimumWidth + minutesMinimumWidth else { return nil }
        return Double(transcriptMinimumWidth / usable)...Double((usable - minutesMinimumWidth) / usable)
    }

    private func transcriptWidth(in usable: CGFloat) -> CGFloat {
        guard let range = allowedRatioRange(in: usable) else { return usable / 2 }
        return usable * CGFloat(min(max(transcriptRatio, range.lowerBound), range.upperBound))
    }

    private func splitHandle(usable: CGFloat) -> some View {
        ZStack {
            Color.clear
            Rectangle()
                .fill(Color.secondary.opacity(splitDragStart == nil ? 0.18 : 0.38))
                .frame(width: 1)
        }
        .frame(width: 10)
        .contentShape(Rectangle())
        .onHover { inside in
            if inside {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
        .gesture(
            // 用全局坐标系：分隔条自身会随比例移动，局部坐标下的 translation 会自我抵消。
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    guard usable > 0, let range = allowedRatioRange(in: usable) else { return }
                    // 起点用「当前显示的比例」，窗口变窄导致比例被夹住时不会跳一下。
                    if splitDragStart == nil {
                        splitDragStart = min(max(transcriptRatio, range.lowerBound), range.upperBound)
                    }
                    let base = splitDragStart ?? transcriptRatio
                    let delta = Double(value.translation.width / usable)
                    transcriptRatio = min(range.upperBound, max(range.lowerBound, base + delta))
                }
                .onEnded { _ in splitDragStart = nil }
        )
        .accessibilityLabel("调整转写与纪要栏宽度")
        .accessibilityHint("左右拖动改变两栏比例")
    }

    private func meetingHeader(_ detail: MeetingDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("会议标题", text: $titleDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18, weight: .semibold))
                    .onSubmit {
                        Task {
                            await environment.renameMeeting(id: detail.meta.id, title: titleDraft)
                            await reload()
                        }
                    }

                moreMenu(detail)
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

    private func moreMenu(_ detail: MeetingDetail) -> some View {
        Menu {
            Button("复制转写") { copyTranscript(detail) }
            Button("导出纪要…") { exportMinutes(title: detail.meta.title) }
                .disabled(minutesText.isEmpty)
            Button("在 Finder 中显示") { revealMeeting(id: detail.meta.id) }
            Divider()
            Button("删除会议", role: .destructive) { showDeleteConfirm = true }
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("更多操作")
        .accessibilityLabel("更多操作")
    }

    private func transcriptSection(_ detail: MeetingDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("转写")
                    .font(.system(size: 13, weight: .semibold))
                    .help("回车保存单条修改")

                if !searchText.isEmpty {
                    Text("\(filteredEntries(detail).count) 条命中")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)
                TextField("搜索转写", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 100, maxWidth: 180)
            }

            let visibleEntries = filteredEntries(detail)

            if visibleEntries.isEmpty {
                Text(detail.entries.isEmpty ? "这场会议没有转写内容。" : "没有匹配的转写。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(visibleEntries) { entry in
                            TranscriptRow(
                                entry: entry,
                                startedAt: detail.meta.startedAt,
                                query: searchText,
                                isHighlighted: entry.id == highlightedEntryID
                            ) { text in
                                Task {
                                    await environment.updateTranscript(
                                        meetingID: detail.meta.id,
                                        entryID: entry.id,
                                        text: text
                                    )
                                }
                            }
                            .id(entry.id)
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.vertical, 4)
                }
                // 用 scrollPosition 而不是 ScrollViewReader：LazyVStack 下后者会按估算高度滚过头。
                .scrollPosition(id: $scrollTargetEntryID, anchor: .center)
                .onChange(of: searchText) { _, _ in
                    // 过滤会重建行集合，清掉定位目标避免跳位。
                    scrollTargetEntryID = nil
                }
                .frame(minHeight: 120, maxHeight: .infinity)
            }
        }
    }

    private func minutesSection(_ detail: MeetingDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("会议纪要")
                    .font(.system(size: 13, weight: .semibold))

                Spacer(minLength: 8)

                if !minutesText.isEmpty && !isGenerating {
                    Picker("", selection: $isEditingMinutes) {
                        Text("预览").tag(false)
                        Text("编辑").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }

                Button("模板…") {
                    showTemplateManager = true
                }
            }
            .controlSize(.small)

            // 右栏宽度只有窗口的一半左右，模板与语言各占一行，避免和右上角按钮抢位置。
            HStack(spacing: 8) {
                Picker("模板", selection: $selectedTemplateID) {
                    ForEach(templates) { template in
                        Text(template.name).tag(Optional(template.id))
                    }
                }
                .frame(minWidth: 120, maxWidth: 200)

                Picker("输出语言", selection: $minutesLanguage) {
                    ForEach(TranslationPrompt.supportedTargetLanguages, id: \.id) { language in
                        Text(language.name).tag(language.id)
                    }
                }
                .frame(minWidth: 100, maxWidth: 130)

                Spacer(minLength: 0)
            }
            .controlSize(.small)

            minutesBody(detail)

            if isGenerating {
                generationProgress
            }

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
                        // 停止后由生成任务把已产出的内容落盘，这里只负责取消。
                        generationTask?.cancel()
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
                MarkdownPreview(text: minutesText, startedAt: detail.meta.startedAt) { token in
                    seek(to: token, in: detail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
            .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - 生成进度

    private var generationProgress: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let progress = segmentProgress {
                ProgressView(value: progress)
            } else {
                ProgressView().progressViewStyle(.linear)
            }
            Text("已生成 \(minutesText.count) 字")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    /// 从「正在提炼第 2/3 段…」里解析进度；不分段时返回 nil，进度条改为不确定态。
    private var segmentProgress: Double? {
        guard let regex = try? NSRegularExpression(pattern: #"第\s*(\d+)\s*/\s*(\d+)\s*段"#) else {
            return nil
        }
        let text = phaseText as NSString
        guard let match = regex.firstMatch(in: phaseText, range: NSRange(location: 0, length: text.length)),
              match.numberOfRanges == 3,
              let current = Int(text.substring(with: match.range(at: 1))),
              let total = Int(text.substring(with: match.range(at: 2))),
              total > 0
        else { return nil }
        return Double(current) / Double(total)
    }

    // MARK: - 定位 / 会议信息 / 更多操作

    /// 纪要里的时间标记 → 滚动到对应转写并短暂高亮。
    private func seek(to token: String, in detail: MeetingDetail) {
        guard let entry = nearestEntry(for: token, in: detail.entries) else { return }
        if detailTab != .content { detailTab = .content }
        if !searchText.isEmpty { searchText = "" }
        highlightedEntryID = entry.id
        scrollTargetEntryID = entry.id
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if highlightedEntryID == entry.id {
                highlightedEntryID = nil
            }
        }
    }

    private func nearestEntry(for token: String, in entries: [TranscriptEntry]) -> TranscriptEntry? {
        let parts = token.split(separator: ":").compactMap { Int($0) }
        guard !parts.isEmpty, !entries.isEmpty else { return nil }

        if parts.count == 3 {
            let target = String(format: "%02d:%02d:%02d", parts[0], parts[1], parts[2])
            if let exact = entries.first(where: { clockString($0.time) == target }) {
                return exact
            }
        }

        let seconds: Int
        switch parts.count {
        case 3: seconds = parts[0] * 3600 + parts[1] * 60 + parts[2]
        case 2: seconds = parts[0] * 60 + parts[1]
        default: return nil
        }

        guard let start = entries.map(\.time).min() else { return nil }
        return entries.min {
            abs($0.time.timeIntervalSince(start) - Double(seconds))
                < abs($1.time.timeIntervalSince(start) - Double(seconds))
        }
    }

    private func meetingInfo(_ detail: MeetingDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            infoRow("开始", dateString(detail.meta.startedAt))
            infoRow("结束", detail.meta.endedAt.map(dateString) ?? "未记录")
            infoRow("时长", durationString(detail.meta.duration))
            infoRow("转写", "\(detail.entries.count) 句")
            infoRow("语言", languageSummary(detail.meta.languages))
            infoRow("纪要", detail.minutes == nil ? "未生成" : "已生成 · \(detail.minutes?.count ?? 0) 字")
            infoRow("存储位置", meetingDirectory(id: detail.meta.id).path)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)
            Text(value)
                .font(.system(size: 12))
                .textSelection(.enabled)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
    }

    private func languageSummary(_ languages: [String: String]) -> String {
        guard !languages.isEmpty else { return "未记录" }
        return AudioChannel.allCases.compactMap { channel in
            guard let identifier = languages[channel.rawValue] else { return nil }
            return "\(channel.displayName)：\(identifier)"
        }
        .joined(separator: " · ")
    }

    private func copyTranscript(_ detail: MeetingDetail) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(MinutesGenerator.transcriptText(detail.entries), forType: .string)
        phaseText = "已复制转写"
    }

    private func meetingDirectory(id: String) -> URL {
        environment.paths.meetingsDirectory.appendingPathComponent(id, isDirectory: true)
    }

    private func revealMeeting(id: String) {
        NSWorkspace.shared.activateFileViewerSelecting([meetingDirectory(id: id)])
    }

    private func deleteMeeting(_ detail: MeetingDetail) {
        Task {
            await environment.deleteMeeting(id: detail.meta.id)
            selectedID = nil
            self.detail = nil
            await reload()
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
            environment.reportMessage(
                "导出失败：\(error.localizedDescription)",
                title: "纪要导出失败",
                code: "MINUTES_EXPORT"
            )
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
                if minutesText.isEmpty {
                    phaseText = "已停止"
                } else {
                    // 中途停止时保留已生成的部分，避免用户白等。
                    await environment.saveMinutes(minutesText, meetingID: detail.meta.id)
                    phaseText = "已停止，保留已生成的 \(minutesText.count) 字"
                    await reload()
                }
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
        // 换了会议，旧的定位目标不再适用，清掉避免滚动位置串场。
        scrollTargetEntryID = nil
        highlightedEntryID = nil
        searchText = ""
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

    private func relativeDateString(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "今天 \(timeString(date))" }
        if calendar.isDateInYesterday(date) { return "昨天 \(timeString(date))" }
        return dateString(date)
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

    /// 带秒的时钟串，用于和纪要里的时间标记对齐。
    private func clockString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
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
    let startedAt: Date
    var query: String = ""
    var isHighlighted: Bool = false
    let onSave: (String) -> Void

    @State private var text: String

    init(
        entry: TranscriptEntry,
        startedAt: Date,
        query: String = "",
        isHighlighted: Bool = false,
        onSave: @escaping (String) -> Void
    ) {
        self.entry = entry
        self.startedAt = startedAt
        self.query = query
        self.isHighlighted = isHighlighted
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
                if trimmedQuery.isEmpty {
                    TextField("", text: $text, axis: .vertical)
                        .textFieldStyle(.plain)
                        .accessibilityLabel("\(entry.speaker.displayName)的发言")
                        .font(.system(size: 12))
                        .onSubmit { onSave(text) }
                } else {
                    // 搜索时切成只读文本，命中处高亮；清空搜索即可继续编辑。
                    Text(highlighted(entry.text))
                        .font(.system(size: 12))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let translation = entry.translation, !translation.isEmpty {
                    if trimmedQuery.isEmpty {
                        Text(translation)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    } else {
                        Text(highlighted(translation))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHighlighted ? Color.accentColor.opacity(0.14) : Color.clear)
        )
        .animation(.easeOut(duration: 0.2), value: isHighlighted)
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func highlighted(_ source: String) -> AttributedString {
        var attributed = AttributedString(source)
        let needle = trimmedQuery
        guard !needle.isEmpty else { return attributed }

        var searchStart = source.startIndex
        while searchStart < source.endIndex,
              let found = source.range(of: needle, options: [.caseInsensitive], range: searchStart..<source.endIndex) {
            let offset = source.distance(from: source.startIndex, to: found.lowerBound)
            let length = source.distance(from: found.lowerBound, to: found.upperBound)
            let start = attributed.index(attributed.startIndex, offsetByCharacters: offset)
            let end = attributed.index(start, offsetByCharacters: length)
            attributed[start..<end].backgroundColor = .yellow.opacity(0.35)
            attributed[start..<end].inlinePresentationIntent = .stronglyEmphasized
            searchStart = found.upperBound
        }
        return attributed
    }

    /// 转写行显示相对会议开始的 mm:ss，与原型和纪要里的定位标签保持一致。
    private var timeString: String {
        let seconds = max(0, Int(entry.time.timeIntervalSince(startedAt)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
struct MinutesTemplateSheet: View {
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
    /// 会议开始时间，用来把绝对时间标记换算成转写里的 mm:ss。
    var startedAt: Date?
    /// 行内出现时间标记时的跳转回调（纪要行动项 → 转写定位）。
    var onSeek: ((String) -> Void)?

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
            seekable(String(line.dropFirst(6))) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: line.hasPrefix("- [x] ") ? "checkmark.square" : "square")
                        .foregroundStyle(.secondary)
                    inline(String(line.dropFirst(6)))
                }
                .font(.system(size: 13))
            }
        } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
            seekable(String(line.dropFirst(2))) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("•").foregroundStyle(.secondary)
                    inline(String(line.dropFirst(2)))
                }
                .font(.system(size: 13))
            }
        } else {
            seekable(line) {
                inline(line).font(.system(size: 13))
            }
        }
    }

    /// 行尾挂一个「定位 hh:mm:ss」按钮，把纪要里的时间标记连回转写。
    @ViewBuilder
    private func seekable<Content: View>(_ source: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            content()
            if let token = Self.timestamp(in: source), let onSeek {
                Spacer(minLength: 4)
                Button("定位 \(displayToken(token))") { onSeek(token) }
                    .buttonStyle(.link)
                    .font(.system(size: 10))
                    .help("在转写中定位 \(displayToken(token))")
            }
        }
    }

    /// 绝对时间（hh:mm:ss）换算为距会议开始的 mm:ss，和转写行显示口径一致。
    private func displayToken(_ token: String) -> String {
        guard let startedAt else { return token }
        let parts = token.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2 else { return token }
        let absolute = parts.count == 3
            ? parts[0] * 3600 + parts[1] * 60 + parts[2]
            : parts[0] * 60 + parts[1]
        let components = Calendar.current.dateComponents([.hour, .minute, .second], from: startedAt)
        let start = (components.hour ?? 0) * 3600 + (components.minute ?? 0) * 60 + (components.second ?? 0)
        var offset = absolute - start
        if offset < 0 { offset += 24 * 3600 }
        return String(format: "%02d:%02d", offset / 60, offset % 60)
    }

    private static func timestamp(in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"\b(\d{1,2}:\d{2}(?::\d{2})?)\b"#) else {
            return nil
        }
        let nsText = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)),
              match.numberOfRanges > 1
        else { return nil }
        return nsText.substring(with: match.range(at: 1))
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
