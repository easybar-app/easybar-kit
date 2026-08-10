import Foundation

private let sliderAutoHideDelay: Duration = .milliseconds(800)

extension VolumeSliderNativeWidget {

  /// Schedules hiding the slider shortly after interaction.
  func scheduleAutoHide() {
    cancelAutoHide()

    let taskID = nextAutoHideTaskID
    nextAutoHideTaskID &+= 1
    autoHideTaskID = taskID

    autoHideTask = Task { [weak self] in
      do {
        try await Task.sleep(for: sliderAutoHideDelay)
      } catch {
        return
      }

      guard let self else { return }
      guard self.autoHideTaskID == taskID else { return }
      self.autoHideTask = nil
      self.autoHideTaskID = nil
      self.isHovered = false
      self.publish()
    }
  }

  /// Cancels a pending auto-hide.
  func cancelAutoHide() {
    autoHideTask?.cancel()
    autoHideTask = nil
    autoHideTaskID = nil
  }

  /// Resolves the volume icon.
  func resolvedIcon(for value: Double, muted: Bool, config: Config.VolumeBuiltinConfig) -> String {
    if muted {
      return config.mutedIcon
    }

    if value < 0.5 {
      return config.lowIcon
    }

    return config.highIcon
  }
}
