import CoreAudio
import Foundation

extension VolumeSliderNativeWidget {
  private static let outputElements: [AudioObjectPropertyElement] = [
    kAudioObjectPropertyElementMain,
    1,
    2,
  ]

  /// Converts the slider-range value back to a normalized system volume.
  func normalizedSliderValue(_ value: Double, config: Config.VolumeBuiltinConfig) -> Double {
    let span = max(config.maxValue - config.minValue, 0.0001)
    return (value - config.minValue) / span
  }

  /// Returns the current system volume state.
  func currentSystemVolumeState(config: Config.VolumeBuiltinConfig) -> SystemVolumeState {
    guard let deviceID = defaultOutputDeviceID() else {
      return makeSystemVolumeState(
        normalizedVolume: 0,
        isMuted: false,
        capabilities: .unavailable,
        config: config
      )
    }

    let capabilities = audioDeviceCapabilities(deviceID: deviceID)
    let systemVolume = readSystemVolume(deviceID: deviceID) ?? 0
    let isMuted = readMutedState(deviceID: deviceID) ?? false

    return makeSystemVolumeState(
      normalizedVolume: systemVolume,
      isMuted: isMuted,
      capabilities: capabilities,
      config: config
    )
  }

  /// Returns capabilities for the current default output device.
  func currentAudioDeviceCapabilities() -> AudioDeviceCapabilities {
    guard let deviceID = defaultOutputDeviceID() else { return .unavailable }
    return audioDeviceCapabilities(deviceID: deviceID)
  }

  /// Reads the current system volume, preferring a main channel and averaging stereo channels.
  func readSystemVolume() -> Double {
    guard let deviceID = defaultOutputDeviceID() else { return 0 }
    return readSystemVolume(deviceID: deviceID) ?? 0
  }

  /// Reads the current muted state from the main or available output channels.
  func readMutedState() -> Bool {
    guard let deviceID = defaultOutputDeviceID() else { return false }
    return readMutedState(deviceID: deviceID) ?? false
  }

  /// Sets the system volume on every writable output element.
  @discardableResult
  func setSystemVolume(_ volume: Double) -> Bool {
    guard let deviceID = defaultOutputDeviceID() else {
      logger.warn("volume write failed, default output device unavailable")
      return false
    }

    let clamped = min(max(volume, 0), 1)
    let scalar = Float32(clamped)
    let writableElements = Self.outputElements.filter {
      propertyIsSettable(
        selector: kAudioDevicePropertyVolumeScalar,
        deviceID: deviceID,
        element: $0
      )
    }

    guard !writableElements.isEmpty else {
      logger.warn("volume write unsupported by current output device")
      return false
    }

    let wroteAny = writableElements.reduce(false) { result, element in
      writeSystemVolumeScalar(scalar, deviceID: deviceID, element: element) || result
    }

    guard wroteAny else {
      logger.warn("volume write failed for all writable output elements")
      return false
    }

    if clamped > 0, audioDeviceCapabilities(deviceID: deviceID).canMute {
      _ = setMutedState(false, deviceID: deviceID)
    }

    return true
  }

  /// Sets the mute state on the current default output device when supported.
  @discardableResult
  func setMutedState(_ muted: Bool) -> Bool {
    guard let deviceID = defaultOutputDeviceID() else {
      logger.warn("mute write failed, default output device unavailable")
      return false
    }

    return setMutedState(muted, deviceID: deviceID)
  }

  /// Returns the default output device.
  func defaultOutputDeviceID() -> AudioDeviceID? {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultOutputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )

    var deviceID = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)

    let status = AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject),
      &address,
      0,
      nil,
      &size,
      &deviceID
    )

    guard status == noErr, deviceID != kAudioObjectUnknown else {
      return nil
    }

    return deviceID
  }

  private func makeSystemVolumeState(
    normalizedVolume: Double,
    isMuted: Bool,
    capabilities: AudioDeviceCapabilities,
    config: Config.VolumeBuiltinConfig
  ) -> SystemVolumeState {
    let clampedSystem = min(max(normalizedVolume, 0), 1)
    let step = max(config.step, 0.0001)
    let sliderValue = config.minValue + clampedSystem * (config.maxValue - config.minValue)
    let roundedValue = (sliderValue / step).rounded() * step

    return SystemVolumeState(
      clampedSystem: clampedSystem,
      roundedValue: roundedValue,
      step: step,
      isMuted: isMuted,
      capabilities: capabilities
    )
  }

  private func audioDeviceCapabilities(deviceID: AudioDeviceID) -> AudioDeviceCapabilities {
    AudioDeviceCapabilities(
      canReadVolume: Self.outputElements.contains {
        hasProperty(
          selector: kAudioDevicePropertyVolumeScalar,
          deviceID: deviceID,
          element: $0
        )
      },
      canSetVolume: Self.outputElements.contains {
        propertyIsSettable(
          selector: kAudioDevicePropertyVolumeScalar,
          deviceID: deviceID,
          element: $0
        )
      },
      canMute: Self.outputElements.contains {
        propertyIsSettable(
          selector: kAudioDevicePropertyMute,
          deviceID: deviceID,
          element: $0
        )
      }
    )
  }

  private func readSystemVolume(deviceID: AudioDeviceID) -> Double? {
    if let main = readVolumeScalar(
      deviceID: deviceID,
      element: kAudioObjectPropertyElementMain
    ) {
      return main
    }

    let channelValues = [1, 2].compactMap { element in
      readVolumeScalar(deviceID: deviceID, element: AudioObjectPropertyElement(element))
    }

    guard !channelValues.isEmpty else { return nil }
    return channelValues.reduce(0, +) / Double(channelValues.count)
  }

  private func readMutedState(deviceID: AudioDeviceID) -> Bool? {
    let values = Self.outputElements.compactMap { element in
      readMuteState(deviceID: deviceID, element: element)
    }

    guard !values.isEmpty else { return nil }
    return values.contains(true)
  }

  private func readVolumeScalar(
    deviceID: AudioDeviceID,
    element: AudioObjectPropertyElement
  ) -> Double? {
    var address = propertyAddress(
      selector: kAudioDevicePropertyVolumeScalar,
      element: element
    )
    guard AudioObjectHasProperty(deviceID, &address) else { return nil }

    var value = Float32(0)
    var size = UInt32(MemoryLayout<Float32>.size)
    let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value)
    return status == noErr ? Double(value) : nil
  }

  private func readMuteState(
    deviceID: AudioDeviceID,
    element: AudioObjectPropertyElement
  ) -> Bool? {
    var address = propertyAddress(selector: kAudioDevicePropertyMute, element: element)
    guard AudioObjectHasProperty(deviceID, &address) else { return nil }

    var value = UInt32(0)
    var size = UInt32(MemoryLayout<UInt32>.size)
    let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value)
    return status == noErr ? value != 0 : nil
  }

  /// Writes one scalar volume value to one output element.
  @discardableResult
  private func writeSystemVolumeScalar(
    _ value: Float32,
    deviceID: AudioDeviceID,
    element: AudioObjectPropertyElement
  ) -> Bool {
    var address = propertyAddress(
      selector: kAudioDevicePropertyVolumeScalar,
      element: element
    )

    guard propertyIsSettable(address: &address, deviceID: deviceID) else {
      return false
    }

    var mutableValue = value
    let status = AudioObjectSetPropertyData(
      deviceID,
      &address,
      0,
      nil,
      UInt32(MemoryLayout<Float32>.size),
      &mutableValue
    )

    if status != noErr {
      logger.warn(
        "volume write failed",
        .field("element", element),
        .field("status", status)
      )
    }
    return status == noErr
  }

  /// Sets the mute state on every writable output element.
  @discardableResult
  private func setMutedState(_ muted: Bool, deviceID: AudioDeviceID) -> Bool {
    let writableElements = Self.outputElements.filter {
      propertyIsSettable(
        selector: kAudioDevicePropertyMute,
        deviceID: deviceID,
        element: $0
      )
    }

    guard !writableElements.isEmpty else {
      logger.warn("mute write unsupported by current output device")
      return false
    }

    let wroteAny = writableElements.reduce(false) { result, element in
      writeMuteState(muted, deviceID: deviceID, element: element) || result
    }

    if !wroteAny {
      logger.warn("mute write failed for all writable output elements")
    }
    return wroteAny
  }

  private func writeMuteState(
    _ muted: Bool,
    deviceID: AudioDeviceID,
    element: AudioObjectPropertyElement
  ) -> Bool {
    var address = propertyAddress(selector: kAudioDevicePropertyMute, element: element)
    guard propertyIsSettable(address: &address, deviceID: deviceID) else { return false }

    var value: UInt32 = muted ? 1 : 0
    let status = AudioObjectSetPropertyData(
      deviceID,
      &address,
      0,
      nil,
      UInt32(MemoryLayout<UInt32>.size),
      &value
    )

    if status != noErr {
      logger.warn(
        "mute write failed",
        .field("element", element),
        .field("status", status)
      )
    }
    return status == noErr
  }

  private func hasProperty(
    selector: AudioObjectPropertySelector,
    deviceID: AudioDeviceID,
    element: AudioObjectPropertyElement
  ) -> Bool {
    var address = propertyAddress(selector: selector, element: element)
    return AudioObjectHasProperty(deviceID, &address)
  }

  private func propertyIsSettable(
    selector: AudioObjectPropertySelector,
    deviceID: AudioDeviceID,
    element: AudioObjectPropertyElement
  ) -> Bool {
    var address = propertyAddress(selector: selector, element: element)
    return propertyIsSettable(address: &address, deviceID: deviceID)
  }

  private func propertyIsSettable(
    address: inout AudioObjectPropertyAddress,
    deviceID: AudioDeviceID
  ) -> Bool {
    guard AudioObjectHasProperty(deviceID, &address) else { return false }
    var settable = DarwinBoolean(false)
    let status = AudioObjectIsPropertySettable(deviceID, &address, &settable)
    return status == noErr && settable.boolValue
  }

  private func propertyAddress(
    selector: AudioObjectPropertySelector,
    element: AudioObjectPropertyElement
  ) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
      mSelector: selector,
      mScope: kAudioDevicePropertyScopeOutput,
      mElement: element
    )
  }
}
