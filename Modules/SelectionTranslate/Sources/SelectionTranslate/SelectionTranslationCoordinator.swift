import AppKit
import Combine
import Foundation
import Settings
import os

/// 串联全局快捷键、取词与浮窗翻译。
@MainActor
public final class SelectionTranslationCoordinator {
    private let reader: any SelectedTextProviding
    private let panel: TranslationPanelController
    private let hotkeys = HotkeyManager()
    private let settingsStore: SettingsStore
    private let logger = Logger(subsystem: "com.lingolens.mac", category: "selection")
    private var cancellables = Set<AnyCancellable>()
    private var started = false

    public init(
        service: TranslationService,
        settingsStore: SettingsStore,
        reader: any SelectedTextProviding = SystemSelectionReader()
    ) {
        self.reader = reader
        self.panel = TranslationPanelController(service: service)
        self.settingsStore = settingsStore
        hotkeys.onHotkey = { [weak self] in
            self?.trigger()
        }
    }

    public func start() {
        guard !started else { return }
        started = true
        let registered = hotkeys.register(settingsStore.settings.general.hotkey)
        logger.info("selection hotkey registered: \(registered)")
        settingsStore.$settings
            .map(\.general.hotkey)
            .removeDuplicates()
            .sink { [weak self] spec in
                self?.hotkeys.register(spec)
            }
            .store(in: &cancellables)
    }

    public var isHotkeyRegistered: Bool {
        hotkeys.isRegistered
    }

    public func trigger() {
        logger.info("selection trigger")
        Task { @MainActor in
            let selection = await reader.readSelectedText()
            logger.info("selected text length: \(selection?.text.count ?? 0)")
            panel.show(text: selection?.text, near: NSEvent.mouseLocation)
        }
    }

    /// 直接翻译给定文本（供界面按钮、剪贴板入口使用）。
    public func translate(text: String) {
        panel.show(text: text, near: NSEvent.mouseLocation)
    }

    /// 打开空白浮窗，手动输入。
    public func openManualPanel() {
        panel.show(text: nil, near: NSEvent.mouseLocation)
    }

    public var hotkeyDisplay: String {
        settingsStore.settings.general.hotkey.displayString
    }

    public func hidePanel() {
        panel.hide()
    }
}
