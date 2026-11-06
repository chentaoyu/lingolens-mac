import AppKit
import Foundation
import LLMClient
import SwiftUI

@MainActor
public final class TranslationPanelModel: ObservableObject {
    public enum Phase: Equatable {
        case idle
        case loading
        case streaming
        case finished
        case failed(String)
    }

    @Published public var originalText: String = ""
    @Published public private(set) var translatedText: String = ""
    @Published public private(set) var phase: Phase = .idle
    @Published public private(set) var modelName: String = ""
    @Published public private(set) var footer: String = ""
    @Published public var isPinned: Bool = false

    public var onClose: (() -> Void)?
    public var onPinChanged: ((Bool) -> Void)?

    private let service: TranslationService
    private var task: Task<Void, Never>?
    private var metrics: ChatMetrics?
    private var targetLanguage: String = ""

    public init(service: TranslationService) {
        self.service = service
    }

    public func prepareForManualInput() {
        task?.cancel()
        phase = .idle
        translatedText = ""
        metrics = nil
        footer = ""
    }

    public func show(text: String) {
        originalText = text
        retranslate()
    }

    public func retranslate() {
        task?.cancel()
        let text = originalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            phase = .idle
            return
        }
        translatedText = ""
        metrics = nil
        footer = ""
        modelName = ""
        phase = .loading
        targetLanguage = ""

        task = Task { @MainActor in
            do {
                for try await event in self.service.translate(text: text) {
                    if Task.isCancelled { return }
                    switch event {
                    case let .modelResolved(name):
                        self.modelName = name
                    case let .delta(delta):
                        if self.phase != .streaming {
                            self.phase = .streaming
                        }
                        self.translatedText += delta
                    case let .finished(metrics):
                        self.metrics = metrics
                        self.phase = .finished
                        self.updateFooter()
                    }
                }
                if self.phase != .finished {
                    self.phase = .finished
                }
                self.updateFooter()
            } catch is CancellationError {
                return
            } catch {
                self.phase = .failed(error.localizedDescription)
            }
        }
    }

    public func cancel() {
        task?.cancel()
        task = nil
    }

    public func copyTranslation() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(translatedText, forType: .string)
    }

    public func togglePin() {
        isPinned.toggle()
        onPinChanged?(isPinned)
    }

    public var placeholderText: String {
        switch phase {
        case .idle:
            return originalText.isEmpty ? "输入要翻译的文本，⌘↩ 开始翻译" : "⌘↩ 开始翻译"
        case .loading:
            return "模型加载中…"
        case .streaming:
            return "翻译中…"
        case .finished:
            return translatedText.isEmpty ? "没有返回内容" : ""
        case let .failed(message):
            return "翻译失败：\(message)"
        }
    }

    public var isFailure: Bool {
        if case .failed = phase { return true }
        return false
    }

    private func updateFooter() {
        var parts: [String] = []
        if !modelName.isEmpty { parts.append(modelName) }
        if let metrics {
            if let ttft = metrics.timeToFirstToken {
                parts.append(String(format: "首字 %.2fs", ttft))
            }
            if let tps = metrics.tokensPerSecond {
                parts.append(String(format: "%.1f tok/s", tps))
            } else if let tokens = metrics.usage?.completionTokens {
                parts.append("\(tokens) tokens")
            }
        }
        footer = parts.joined(separator: " · ")
    }
}
