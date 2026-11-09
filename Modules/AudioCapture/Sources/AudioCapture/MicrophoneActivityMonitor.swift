import AppKit
import AVFoundation
import CoreAudio
import Foundation

/// 监听「是否有别的应用正在使用麦克风」。
///
/// 用 CoreAudio 的进程对象列表 + 每个进程的 IsRunningInput，
/// 排除自己（否则本应用一采集麦克风就会把自己当成「别人在用」）。
/// 这样既能知道会议软件何时开麦，也能知道它何时闭麦。
@MainActor
public final class MicrophoneActivityMonitor: ObservableObject {
    /// 当前是否有其他进程在使用麦克风。
    @Published public private(set) var isOtherAppUsingInput = false
    /// 正在使用麦克风的应用名（仅用于展示）。
    @Published public private(set) var activeAppNames: [String] = []

    /// 默认输入设备是否被任何进程占用（含自己）。
    public var isDeviceRunningSomewhere: Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let device = Self.defaultInputDevice()
        guard device != kAudioObjectUnknown,
              AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr
        else { return false }
        return value != 0
    }

    private var task: Task<Void, Never>?

    public init() {}

    /// 开始轮询。1 秒一次：麦克风开关状态不是高频事件，轮询足够且比属性监听更好移植。
    public func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                self?.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    /// 立刻刷新一次。
    public func refresh() {
        let me = getpid()
        var names: [String] = []
        for object in Self.processObjects() where Self.isRunningInput(object) {
            let pid = Self.pid(of: object)
            guard pid > 0, pid != me else { continue }
            names.append(Self.appName(pid: pid))
        }
        let sorted = Array(Set(names)).sorted()
        if sorted != activeAppNames { activeAppNames = sorted }
        let active = !sorted.isEmpty
        if active != isOtherAppUsingInput { isOtherAppUsingInput = active }
    }

    // MARK: - CoreAudio

    private static func defaultInputDevice() -> AudioObjectID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return device
    }

    private static func processObjects() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        ) == noErr else { return [] }
        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        guard count > 0 else { return [] }
        var list = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &list
        ) == noErr else { return [] }
        return list
    }

    private static func pid(of object: AudioObjectID) -> pid_t {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: pid_t = -1
        var size = UInt32(MemoryLayout<pid_t>.size)
        AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value)
        return value
    }

    private static func isRunningInput(_ object: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningInput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return false }
        return value != 0
    }

    private static func appName(pid: pid_t) -> String {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return "pid \(pid)" }
        return app.localizedName ?? app.bundleIdentifier ?? "pid \(pid)"
    }
}
