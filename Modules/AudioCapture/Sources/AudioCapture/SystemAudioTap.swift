import AVFoundation
import CoreAudio
import Foundation

public enum SystemAudioTapError: Error, LocalizedError {
    case tapCreationFailed(OSStatus)
    case aggregateDeviceFailed(OSStatus)
    case formatUnavailable
    case ioProcFailed(OSStatus)
    case startFailed(OSStatus)

    public var errorDescription: String? {
        switch self {
        case let .tapCreationFailed(status):
            return "无法创建系统音频 Tap（\(status)）。请在系统设置中允许 LingoLens 录制系统音频。"
        case let .aggregateDeviceFailed(status):
            return "无法创建系统音频聚合设备（\(status)）。"
        case .formatUnavailable:
            return "无法读取系统音频格式。"
        case let .ioProcFailed(status):
            return "无法创建系统音频回调（\(status)）。"
        case let .startFailed(status):
            return "无法启动系统音频采集（\(status)）。"
        }
    }
}

/// 基于 Core Audio Process Tap 的系统音频采集。
public final class SystemAudioTap: @unchecked Sendable {
    private let lock = NSLock()
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var format: AVAudioFormat?
    private let onBuffer: @Sendable (AVAudioPCMBuffer) -> Void

    public init(onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) {
        self.onBuffer = onBuffer
    }

    public func start() throws {
        stop()

        let ownProcess = Self.processObjectID(pid: ProcessInfo.processInfo.processIdentifier)
        let description = CATapDescription(monoGlobalTapButExcludeProcesses: ownProcess.map { [$0] } ?? [])
        description.uuid = UUID()
        description.isPrivate = true

        var newTapID = AudioObjectID(kAudioObjectUnknown)
        let tapStatus = AudioHardwareCreateProcessTap(description, &newTapID)
        guard tapStatus == noErr else { throw SystemAudioTapError.tapCreationFailed(tapStatus) }

        guard let tapFormat = Self.streamFormat(of: newTapID) else {
            AudioHardwareDestroyProcessTap(newTapID)
            throw SystemAudioTapError.formatUnavailable
        }

        let aggregateUID = UUID().uuidString
        var aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "LingoLens System Audio",
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: description.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: true
            ]]
        ]

        // 提供主设备作为聚合设备的时钟源。
        if let outputUID = Self.defaultOutputDeviceUID() {
            aggregateDescription[kAudioAggregateDeviceMainSubDeviceKey] = outputUID
            aggregateDescription[kAudioAggregateDeviceSubDeviceListKey] = [[
                kAudioSubDeviceUIDKey: outputUID
            ]]
        }

        var newAggregateID = AudioObjectID(kAudioObjectUnknown)
        let aggregateStatus = AudioHardwareCreateAggregateDevice(
            aggregateDescription as CFDictionary,
            &newAggregateID
        )
        guard aggregateStatus == noErr else {
            AudioHardwareDestroyProcessTap(newTapID)
            throw SystemAudioTapError.aggregateDeviceFailed(aggregateStatus)
        }

        var newProcID: AudioDeviceIOProcID?
        let procStatus = AudioDeviceCreateIOProcIDWithBlock(
            &newProcID,
            newAggregateID,
            nil
        ) { [weak self] _, inputData, _, _, _ in
            guard let self,
                  let format = self.format,
                  let source = AVAudioPCMBuffer(
                    pcmFormat: format,
                    bufferListNoCopy: inputData,
                    deallocator: nil
                  ),
                  let copy = AudioBufferTools.copy(source)
            else { return }
            self.onBuffer(copy)
        }

        guard procStatus == noErr, let newProcID else {
            AudioHardwareDestroyAggregateDevice(newAggregateID)
            AudioHardwareDestroyProcessTap(newTapID)
            throw SystemAudioTapError.ioProcFailed(procStatus)
        }

        let startStatus = AudioDeviceStart(newAggregateID, newProcID)
        guard startStatus == noErr else {
            AudioDeviceDestroyIOProcID(newAggregateID, newProcID)
            AudioHardwareDestroyAggregateDevice(newAggregateID)
            AudioHardwareDestroyProcessTap(newTapID)
            throw SystemAudioTapError.startFailed(startStatus)
        }

        lock.lock()
        tapID = newTapID
        aggregateDeviceID = newAggregateID
        ioProcID = newProcID
        format = tapFormat
        lock.unlock()
    }

    public func stop() {
        lock.lock()
        let currentAggregate = aggregateDeviceID
        let currentProc = ioProcID
        let currentTap = tapID
        aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
        ioProcID = nil
        tapID = AudioObjectID(kAudioObjectUnknown)
        format = nil
        lock.unlock()

        if currentAggregate != kAudioObjectUnknown, let currentProc {
            AudioDeviceStop(currentAggregate, currentProc)
            AudioDeviceDestroyIOProcID(currentAggregate, currentProc)
        }
        if currentAggregate != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(currentAggregate)
        }
        if currentTap != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(currentTap)
        }
    }

    private static func streamFormat(of objectID: AudioObjectID) -> AVAudioFormat? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var streamDescription = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &streamDescription)
        guard status == noErr else { return nil }
        return AVAudioFormat(streamDescription: &streamDescription)
    }

    private static func defaultOutputDeviceUID() -> String? {
        var deviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var deviceSize = UInt32(MemoryLayout<AudioObjectID>.size)
        let deviceStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &deviceAddress,
            0,
            nil,
            &deviceSize,
            &deviceID
        )
        guard deviceStatus == noErr, deviceID != kAudioObjectUnknown else { return nil }

        var uidAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid: CFString?
        var uidSize = UInt32(MemoryLayout<CFString?>.size)
        let uidStatus = AudioObjectGetPropertyData(deviceID, &uidAddress, 0, nil, &uidSize, &uid)
        guard uidStatus == noErr else { return nil }
        return uid as String?
    }

    private static func processObjectID(pid: pid_t) -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var mutablePID = pid
        var objectID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            UInt32(MemoryLayout<pid_t>.size),
            &mutablePID,
            &size,
            &objectID
        )
        guard status == noErr, objectID != kAudioObjectUnknown else { return nil }
        return objectID
    }
}
