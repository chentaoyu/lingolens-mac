import Combine
import Foundation

/// 设置的内存状态与磁盘落盘（300ms 防抖）。
@MainActor
public final class SettingsStore: ObservableObject {
    @Published public private(set) var settings: AppSettings
    private let fileURL: URL
    private var saveTask: Task<Void, Never>?

    public init(fileURL: URL) {
        self.fileURL = fileURL
        self.settings = SettingsPersistence.load(from: fileURL)
    }

    public init(fileURL: URL, settings: AppSettings) {
        self.fileURL = fileURL
        self.settings = settings
    }

    public func update(_ mutate: (inout AppSettings) -> Void) {
        var copy = settings
        mutate(&copy)
        settings = copy
        scheduleSave()
    }

    public func reload() {
        settings = SettingsPersistence.load(from: fileURL)
    }

    public func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        try? SettingsPersistence.save(settings, to: fileURL)
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }
}
