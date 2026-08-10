struct MicrophoneActivityResolver {
  private(set) var cameraActive = false
  private(set) var deviceFallbackEnabled = true

  mutating func setCameraActive(_ active: Bool) {
    cameraActive = active
    if active {
      deviceFallbackEnabled = false
    }
  }

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

  private func allCaptureSignalsAreInactive(processActive: Bool, deviceActive: Bool) -> Bool {
    !cameraActive && !processActive && !deviceActive
  }

  private var shouldSuppressDeviceFallback: Bool {
    cameraActive || !deviceFallbackEnabled
  }
}
