import Foundation

public struct MinutesTemplate: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var prompt: String

    public init(id: UUID = UUID(), name: String, prompt: String) {
        self.id = id
        self.name = name
        self.prompt = prompt
    }

    public static let standardID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    public static let standard = MinutesTemplate(
        id: standardID,
        name: "标准会议纪要",
        prompt: """
        你是会议纪要助手。请根据转写内容生成 Markdown 格式的会议纪要，包含以下章节：
        ## 摘要
        ## 关键讨论
        ## 决策
        ## 行动项（负责人 / 截止时间）
        ## 待定问题

        只依据转写内容总结，不要编造；信息不足时写“未提及”。
        """
    )
}

/// 自定义纪要模板持久化。
public actor MinutesTemplateStore {
    private let fileURL: URL
    private var templates: [MinutesTemplate]

    public init(fileURL: URL) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([MinutesTemplate].self, from: data) {
            self.templates = decoded
        } else {
            self.templates = [.standard]
        }
        if !self.templates.contains(where: { $0.id == MinutesTemplate.standardID }) {
            self.templates.insert(.standard, at: 0)
        }
    }

    public func all() -> [MinutesTemplate] {
        templates
    }

    @discardableResult
    public func add(name: String, prompt: String) -> MinutesTemplate {
        let template = MinutesTemplate(name: name, prompt: prompt)
        templates.append(template)
        persist()
        return template
    }

    public func update(_ template: MinutesTemplate) {
        guard let index = templates.firstIndex(where: { $0.id == template.id }) else { return }
        templates[index] = template
        persist()
    }

    public func delete(id: UUID) {
        guard id != MinutesTemplate.standardID else { return }
        templates.removeAll { $0.id == id }
        persist()
    }

    public func template(id: UUID) -> MinutesTemplate? {
        templates.first { $0.id == id }
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(templates) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: .atomic)
    }
}
