/// Stores microphone activity resolver data.
struct MicrophoneActivityResolver {
  /// Whether the camera active option is enabled for this microphone activity resolver.
  private(set) var cameraActive = false
  /// Whether the device fallback enabled option is enabled for this microphone activity resolver.
  private(set) var deviceFallbackEnabled = true

  /// Sets camera active.
  mutating func setCameraActive(_ active: Bool) {
    cameraActive = active
    if active {
      deviceFallbackEnabled = false
    }
  }

  /// Resolves the requested value.
  mutating func resolve(processActive: Bool, deviceActive: Bool) -> Bool {
    if allCaptureSignalsAreInactive(processActive: processActive, deviceActive: deviceActive) {
      deviceFallbackEnabled = true
    }

    if processActive {
      return true
    }
    if shouldSuppressDeviceFallback {
      return false
    }
    return deviceActive
  }

  /// Returns the all capture signals are inactive.
  private func allCaptureSignalsAreInactive(processActive: Bool, deviceActive: Bool) -> Bool {
    !cameraActive && !processActive && !deviceActive
  }

  /// Whether the should suppress device fallback option is enabled for this microphone activity resolver.
  private var shouldSuppressDeviceFallback: Bool {
    cameraActive || !deviceFallbackEnabled
  }
}
