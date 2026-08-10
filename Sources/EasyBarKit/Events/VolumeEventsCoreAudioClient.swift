import CoreAudio
import Foundation

/// Injectable CoreAudio operations used by volume-event observation.
struct VolumeEventsCoreAudioClient: @unchecked Sendable {
  typealias ListenerOperation = (
    _ objectID: AudioObjectID,
    _ address: AudioObjectPropertyAddress,
    _ queue: DispatchQueue,
    _ block: @escaping AudioObjectPropertyListenerBlock
  ) -> OSStatus

  let defaultOutputDeviceID: () -> AudioDeviceID?
  let readMutedState: (AudioDeviceID) -> Bool
  let addListener: ListenerOperation
  let removeListener: ListenerOperation

  /// Production client backed by CoreAudio.
  static let system = VolumeEventsCoreAudioClient(
    defaultOutputDeviceID: {
      var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
      )
      var deviceID = AudioDeviceID(kAudioObjectUnknown)
      var size = UInt32(MemoryLayout<AudioDeviceID>.size)
      let status = AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &address,
        0,
        nil,
        &size,
        &deviceID
      )

      guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
      return deviceID
    },
    readMutedState: { deviceID in
      var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
      )
      var muted = UInt32(0)
      var size = UInt32(MemoryLayout<UInt32>.size)
      let status = AudioObjectGetPropertyData(
        deviceID,
        &address,
        0,
        nil,
        &size,
        &muted
      )

      return status == noErr && muted != 0
    },
    addListener: { objectID, address, queue, block in
      var address = address
      return AudioObjectAddPropertyListenerBlock(objectID, &address, queue, block)
    },
    removeListener: { objectID, address, queue, block in
      var address = address
      return AudioObjectRemovePropertyListenerBlock(objectID, &address, queue, block)
    }
  )
}
