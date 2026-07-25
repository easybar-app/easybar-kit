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
    if !cameraActive, !processActive, !deviceActive {
      deviceFallbackEnabled = true
    }

    if processActive {
      return true
    }
    if cameraActive || !deviceFallbackEnabled {
      return false
    }
    return deviceActive
  }
}
