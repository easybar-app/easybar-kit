import EasyBarShared
import Foundation

/// Combines the best event source for each capture-device family.
@MainActor
final class SystemCaptureDeviceInventoryMonitor: CaptureDeviceInventoryMonitoring {
  var onChange: (() -> Void)?

  var devices: [CaptureDeviceState] {
    cameraMonitor.devices + microphoneMonitor.devices
  }

  private let cameraMonitor: CoreMediaIOCameraInventoryMonitor
  private let microphoneMonitor: CoreAudioMicrophoneInventoryMonitor
  private var settleTask: Task<Void, Never>?
  private var started = false

  init(logger: ProcessLogger) {
    cameraMonitor = CoreMediaIOCameraInventoryMonitor(logger: logger.child("camera"))
    microphoneMonitor = CoreAudioMicrophoneInventoryMonitor(logger: logger.child("microphone"))
  }

  func start() {
    guard !started else { return }
    started = true

    cameraMonitor.onChange = { [weak self] in
      self?.handleCameraChange()
    }
    microphoneMonitor.onChange = { [weak self] in
      self?.handleChildChange()
    }

    cameraMonitor.start()
    microphoneMonitor.setCameraActive(cameraMonitor.devices.contains(where: \.active))
    microphoneMonitor.start()
  }

  func stop() {
    guard started else { return }
    started = false

    settleTask?.cancel()
    settleTask = nil
    cameraMonitor.stop()
    microphoneMonitor.stop()
    cameraMonitor.onChange = nil
    microphoneMonitor.onChange = nil
  }

  private func handleCameraChange() {
    guard started else { return }
    microphoneMonitor.setCameraActive(cameraMonitor.devices.contains(where: \.active))
    handleChildChange()
  }

  /// Publishes the native notification immediately, then verifies the combined state once more.
  ///
  /// Camera and microphone frameworks do not always settle their activity properties in the same
  /// callback turn. The delayed read is tied to a native notification and is not periodic polling.
  private func handleChildChange() {
    guard started else { return }
    onChange?()

    settleTask?.cancel()
    settleTask = Task { @MainActor [weak self] in
      do {
        try await Task.sleep(for: .milliseconds(500))
      } catch {
        return
      }

      guard !Task.isCancelled, let self, self.started else { return }
      self.settleTask = nil
      self.onChange?()
    }
  }
}
