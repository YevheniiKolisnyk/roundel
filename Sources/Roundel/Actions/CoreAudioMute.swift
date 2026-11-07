import CoreAudio
import Foundation
import RoundelCore

/// Mute control of the default output device. Uses the master channel, or channels 1 and 2 on devices that only
/// expose per-channel mute. Returns `nil` / throws for devices with no mute control at all.
@MainActor
struct CoreAudioMute: MuteControlling {
    var isMuted: Bool? {
        guard let device = defaultOutputDevice() else { return nil }
        let values = muteElements(of: device).compactMap { element -> Bool? in
            var value: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            var address = Self.address(element)
            guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
            return value != 0
        }
        return values.isEmpty ? nil : values.allSatisfy { $0 }
    }

    func setMuted(_ muted: Bool) throws {
        guard let device = defaultOutputDevice() else { throw ActionError.failed("no output device") }
        let elements = muteElements(of: device)
        guard !elements.isEmpty else { throw ActionError.failed("the current output device does not support mute") }
        var value: UInt32 = muted ? 1 : 0
        for element in elements {
            var address = Self.address(element)
            let status = AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
            guard status == noErr else { throw ActionError.failed("could not change mute (CoreAudio error \(status))") }
        }
    }

    // MARK: Private

    private static func address(_ element: UInt32) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
    }

    private func defaultOutputDevice() -> AudioObjectID? {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    /// The elements that can actually be muted: master if present, else the stereo channels.
    private func muteElements(of device: AudioObjectID) -> [UInt32] {
        func settable(_ element: UInt32) -> Bool {
            var address = Self.address(element)
            guard AudioObjectHasProperty(device, &address) else { return false }
            var isSettable: DarwinBoolean = false
            return AudioObjectIsPropertySettable(device, &address, &isSettable) == noErr && isSettable.boolValue
        }
        if settable(kAudioObjectPropertyElementMain) { return [kAudioObjectPropertyElementMain] }
        return [1, 2].filter(settable)
    }
}
