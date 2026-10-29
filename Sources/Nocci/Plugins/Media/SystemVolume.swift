import AudioToolbox
import CoreAudio
import Foundation

/// Reads and sets the default output device's volume and reports changes (volume or device switch).
@MainActor
final class SystemVolume {
    /// Called with the new volume (0...1), or nil if the current device has no volume control.
    var onChange: ((Float?) -> Void)?

    private var deviceID: AudioDeviceID = AudioObjectID(kAudioObjectUnknown)
    private var block: AudioObjectPropertyListenerBlock?
    private var isListening = false

    private static var defaultDeviceAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    private static var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)

    /// The current output volume, or nil if the device doesn't support it.
    func current() -> Float? {
        let device = Self.defaultDevice()
        guard device != kAudioObjectUnknown else { return nil }
        var address = Self.volumeAddress
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        return status == noErr ? value : nil
    }

    /// Sets the output volume (clamped to 0...1) on the default device.
    func set(_ volume: Float) {
        let device = Self.defaultDevice()
        guard device != kAudioObjectUnknown else { return }
        var address = Self.volumeAddress
        guard AudioObjectHasProperty(device, &address) else { return }
        var value = min(max(volume, 0), 1)
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
    }

    /// Starts listening for volume and default-device changes.
    func start() {
        guard !isListening else { return }
        isListening = true
        let block: AudioObjectPropertyListenerBlock = { @Sendable [weak self] _, _ in
            Task { @MainActor in self?.handleChange() }
        }
        self.block = block
        var address = Self.defaultDeviceAddress
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
        attach(to: Self.defaultDevice())
    }

    /// Stops listening and drops the callback.
    func stop() {
        guard isListening else { return }
        isListening = false
        if let block {
            var address = Self.defaultDeviceAddress
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
        }
        detach()
        block = nil
        onChange = nil
    }

    private func handleChange() {
        guard isListening else { return }
        let device = Self.defaultDevice()
        if device != deviceID {
            detach()
            attach(to: device)
        }
        onChange?(current())
    }

    private func attach(to device: AudioDeviceID) {
        deviceID = device
        guard device != kAudioObjectUnknown, let block else { return }
        var address = Self.volumeAddress
        if AudioObjectHasProperty(device, &address) {
            AudioObjectAddPropertyListenerBlock(device, &address, .main, block)
        }
    }

    private func detach() {
        if deviceID != kAudioObjectUnknown, let block {
            var address = Self.volumeAddress
            if AudioObjectHasProperty(deviceID, &address) {
                AudioObjectRemovePropertyListenerBlock(deviceID, &address, .main, block)
            }
        }
        deviceID = AudioObjectID(kAudioObjectUnknown)
    }

    private static func defaultDevice() -> AudioDeviceID {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = defaultDeviceAddress
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return device
    }
}
