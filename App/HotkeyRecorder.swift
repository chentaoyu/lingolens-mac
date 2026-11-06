import AppKit
import Settings
import SwiftUI

struct HotkeyRecorder: View {
    @Binding var spec: HotkeySpec
    @State private var isRecording = false
    @State private var monitor: Any? = nil

    var body: some View {
        HStack(spacing: 8) {
            Text(spec.displayString)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.secondary.opacity(0.12))
                )

            Button(isRecording ? "请按下快捷键…" : "录制") {
                if isRecording {
                    stop()
                } else {
                    start()
                }
            }
            .controlSize(.small)

            if isRecording {
                Button("取消") {
                    stop()
                }
                .controlSize(.small)
            }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        guard monitor == nil else { return }
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                stop()
                return nil
            }
            let modifiers = Self.carbonModifiers(event.modifierFlags)
            guard modifiers != 0 else { return event }
            spec = HotkeySpec(keyCode: UInt32(event.keyCode), modifiers: modifiers)
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        isRecording = false
    }

    private static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var raw: UInt32 = 0
        if flags.contains(.command) { raw |= HotkeySpec.commandModifier }
        if flags.contains(.option) { raw |= HotkeySpec.optionModifier }
        if flags.contains(.control) { raw |= HotkeySpec.controlModifier }
        if flags.contains(.shift) { raw |= HotkeySpec.shiftModifier }
        return raw
    }
}
