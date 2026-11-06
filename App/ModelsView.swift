import AppKit
import ModelLibrary
import ModelRuntime
import SwiftUI
import UniformTypeIdentifiers

struct ModelsView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var isImporting = false
    @State private var showDownload = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                runtimeBanner
                residentSection
                modelsSection
                serversSection
            }
            .padding(20)
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.folder]) { result in
            switch result {
            case let .success(url):
                Task { await environment.importModel(at: url) }
            case let .failure(error):
                environment.lastError = error.localizedDescription
            }
        }
        .sheet(isPresented: $showDownload) {
            DownloadSheet()
                .environmentObject(environment)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("模型")
                .font(.system(size: 20, weight: .semibold))
            Text("本地 MLX 模型与运行状态")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                Task { await environment.refreshModels() }
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .disabled(environment.isRefreshing)

            Button {
                isImporting = true
            } label: {
                Label("导入", systemImage: "folder.badge.plus")
            }

            Button {
                showDownload = true
            } label: {
                Label("从 Hugging Face 下载", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var runtimeBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: environment.runtimeInstalled ? "checkmark.seal.fill" : "shippingbox")
                .font(.system(size: 20))
                .foregroundStyle(environment.runtimeInstalled ? Color.green : Color.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(environment.runtimeInstalled ? "Python 运行时已就绪" : "准备 Python 运行时")
                    .font(.system(size: 13, weight: .semibold))
                Text(environment.runtimeProgress.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if !environment.runtimeInstalled {
                if case .failed = environment.runtimeProgress.phase {
                    Button("重试") {
                        Task { await environment.installRuntime() }
                    }
                    .controlSize(.small)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Button("打开日志") {
                environment.openLogsFolder()
            }
            .controlSize(.small)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private var residentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("常驻模型")
                .font(.system(size: 13, weight: .semibold))

            HStack(spacing: 12) {
                Picker(
                    "",
                    selection: Binding(
                        get: { environment.settings.residentModelID ?? "" },
                        set: { environment.setResidentModelID($0.isEmpty ? nil : $0) }
                    )
                ) {
                    Text("未设置").tag("")
                    ForEach(environment.models.filter(\.isAvailable)) { record in
                        Text(record.name).tag(record.id)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 360)

                Button("加载常驻模型") {
                    Task { await environment.ensureResidentModel() }
                }
                .controlSize(.small)
                .disabled(environment.residentModel == nil)

                Spacer()
            }

            if let resident = environment.residentModel {
                Text(resident.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                HStack(spacing: 8) {
                    Text("选择一个模型作为常驻模型，应用启动时会自动加载。")
                    Button("下载默认模型…") {
                        showDownload = true
                    }
                    .controlSize(.small)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var modelsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("模型")
                    .font(.system(size: 13, weight: .semibold))
                Text("\(environment.models.count) 个")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            if environment.models.isEmpty {
                ContentUnavailableView(
                    "还没有模型",
                    systemImage: "square.stack.3d.up.slash",
                    description: Text("点击右上角“导入”选择本地模型文件夹，或“下载”从 Hugging Face 获取 MLX 模型。")
                )
                .frame(height: 180)
            } else {
                VStack(spacing: 0) {
                    ForEach(environment.models) { record in
                        ModelRow(record: record)
                        if record.id != environment.models.last?.id {
                            Divider().padding(.leading, 30)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.secondary.opacity(0.06))
                )
            }
        }
    }

    private var serversSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("模型服务")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("空闲卸载与崩溃重启由运行时自动处理")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if environment.servers.isEmpty {
                Text("暂无运行中的模型服务。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(environment.servers, id: \.model.id) { snapshot in
                        HStack(spacing: 10) {
                            ServerStateBadge(state: snapshot.state)
                                .frame(width: 76, alignment: .leading)
                            Text(snapshot.model.name)
                                .font(.system(size: 12))
                            if let pid = snapshot.pid {
                                Text("pid \(pid)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            if snapshot.activeLeases > 0 {
                                Text("请求中 · \(snapshot.activeLeases)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            if snapshot.restartCount > 0 {
                                Text("重启 \(snapshot.restartCount)")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                            Spacer()
                            if case let .failed(message) = snapshot.state {
                                Text(message)
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        if snapshot.model.id != environment.servers.last?.model.id {
                            Divider().padding(.leading, 12)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.secondary.opacity(0.06))
                )
            }
        }
    }
}

private struct ModelRow: View {
    @EnvironmentObject private var environment: AppEnvironment
    let record: ModelRecord

    private var isResident: Bool { environment.settings.residentModelID == record.id }
    private var memoryFit: MemoryFit { MemoryFit.level(record.info?.estimatedMemoryBytes ?? 0) }
    private var canLoad: Bool { record.isAvailable && memoryFit != .insufficient }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: record.info?.supportsVision == true ? "eye.square" : "cpu")
                .font(.title3)
                .foregroundStyle(isResident ? Color.accentColor : .secondary)
                .frame(width: 32, height: 32)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(record.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    if isResident {
                        TagBadge(text: "常驻", color: .accentColor)
                    }
                    if !record.isAvailable {
                        TagBadge(text: "不可用", color: .orange)
                    } else if memoryFit == .insufficient {
                        TagBadge(text: "内存不足", color: .red)
                    }
                    TagBadge(text: record.sourceLabel, color: .secondary)
                }
                if let info = record.info {
                    Text(info.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .help(record.path)

            Spacer(minLength: 12)

            if let bytes = record.info?.estimatedMemoryBytes, bytes > 0 {
                VStack(alignment: .trailing, spacing: 3) {
                    Text("\(formatBytes(UInt64(bytes))) / \(formatBytes(ProcessInfo.processInfo.physicalMemory))")
                        .font(.caption2)
                        .foregroundStyle(memoryFit == .insufficient ? .red : .secondary)
                    MemoryMeter(bytes: bytes, showsLabel: false)
                }
                .frame(width: 130)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("预估内存 \(formatBytes(UInt64(bytes)))，本机 \(formatBytes(ProcessInfo.processInfo.physicalMemory))")
            }

            ServerStateBadge(state: environment.state(for: record))
                .frame(width: 56, alignment: .leading)

            if !isResident {
                Button("设为常驻") {
                    environment.setResidentModelID(record.id)
                }
                .controlSize(.small)
                .disabled(!canLoad)
                .help(canLoad ? "应用启动时自动加载此模型" : "预估内存超过本机内存的 75%，加载可能失败")
            }

            Menu {
                Button("启动服务") {
                    Task { await environment.startServer(for: record) }
                }
                .disabled(!canLoad)
                Button("停止服务") {
                    Task { await environment.stopServer(for: record) }
                }
                Button("重启服务") {
                    Task { await environment.restartServer(for: record) }
                }
                .disabled(!canLoad)
                Divider()
                Button("在 Finder 中显示") {
                    environment.revealInFinder(record)
                }
                Button("查看日志") {
                    environment.openLog(for: record)
                }
                Divider()
                Button(record.source == .downloaded ? "删除模型" : "移出列表", role: .destructive) {
                    Task { await environment.removeModel(record) }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 26)
            .accessibilityLabel("更多操作")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

struct ServerStateBadge: View {
    let state: ServerState

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .help(helpText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("服务状态：\(label)")
    }

    private var label: String {
        switch state {
        case .stopped: return "未运行"
        case .starting: return "启动中"
        case .ready: return "运行中"
        case .stopping: return "停止中"
        case .failed: return "失败"
        }
    }

    private var color: Color {
        switch state {
        case .stopped: return .secondary
        case .starting, .stopping: return .orange
        case .ready: return .green
        case .failed: return .red
        }
    }

    private var helpText: String {
        if case let .ready(url) = state { return url.absoluteString }
        if case let .failed(message) = state { return message }
        return label
    }
}

struct TagBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(color.opacity(0.16)))
            .foregroundStyle(color)
    }
}

extension ModelInfo {
    var summary: String {
        var parts: [String] = []
        if let parameters = parameterCount {
            parts.append(Self.parameterCountString(parameters))
        }
        if let bits = quantizationBits {
            parts.append("\(bits)-bit")
        }
        parts.append(formatBytes(UInt64(max(0, diskSizeBytes))))
        if estimatedMemoryBytes > 0 {
            parts.append("约需 " + formatBytes(UInt64(estimatedMemoryBytes)))
        }
        if supportsVision {
            parts.append("视觉")
        }
        return parts.joined(separator: " · ")
    }

    private static func parameterCountString(_ count: Int64) -> String {
        if count >= 1_000_000_000 {
            return String(format: "%.1fB", Double(count) / 1_000_000_000)
        }
        if count >= 1_000_000 {
            return String(format: "%.0fM", Double(count) / 1_000_000)
        }
        return "\(count)"
    }
}
