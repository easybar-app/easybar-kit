import Foundation

/// Capabilities exposed by the current default audio output device.
struct AudioDeviceCapabilities: Equatable, Sendable {
  let canReadVolume: Bool
  let canSetVolume: Bool
  let canMute: Bool

  static let unavailable = AudioDeviceCapabilities(
    canReadVolume: false,
    canSetVolume: false,
    canMute: false
  )
}

/// Actions exposed by the native volume widget context menu.
enum VolumeContextMenuAction: Equatable {
  case toggleMute
  case toggleShowPercentage
  case toggleExpandOnHover
  case openSoundSettings

  /// Stable context-menu action identifier.
  var id: String {
    switch self {
    case .toggleMute: return "volume.toggle_mute"
    case .toggleShowPercentage: return "volume.toggle_show_percentage"
    case .toggleExpandOnHover: return "volume.toggle_expand_on_hover"
    case .openSoundSettings: return "volume.open_sound_settings"
    }
  }

  /// Decodes one stable context-menu action identifier.
  init?(id: String) {
    switch id {
    case Self.toggleMute.id: self = .toggleMute
    case Self.toggleShowPercentage.id: self = .toggleShowPercentage
    case Self.toggleExpandOnHover.id: self = .toggleExpandOnHover
    case Self.openSoundSettings.id: self = .openSoundSettings
    default: return nil
    }
  }
}

/// Pure presentation decisions shared by the volume widget and its tests.
enum VolumePresentation {
  /// Returns the percentage label for the current interaction mode.
  static func percentageText(
    normalizedVolume: Double,
    config: Config.VolumeBuiltinConfig,
    isHovered: Bool,
    canReadVolume: Bool,
    canSetVolume: Bool
  ) -> String {
    let shouldShow =
      canReadVolume
      && config.showPercentage
      && (!config.expandToSliderOnHover || isHovered || !canSetVolume)

    guard shouldShow else { return "" }
    let clamped = min(max(normalizedVolume, 0), 1)
    return "\(Int((clamped * 100.0).rounded()))%"
  }
}

/// Builds the native volume context menu from current audio and config state.
enum VolumeContextMenu {
  static func make(
    config: Config.VolumeBuiltinConfig,
    isMuted: Bool,
    capabilities: AudioDeviceCapabilities
  ) -> [WidgetContextMenuItem] {
    [
      WidgetContextMenuItem(
        id: VolumeContextMenuAction.toggleMute.id,
        title: isMuted ? "Unmute" : "Mute",
        enabled: capabilities.canMute
      ),
      WidgetContextMenuItem(separator: true),
      WidgetContextMenuItem(
        id: VolumeContextMenuAction.toggleShowPercentage.id,
        title: "Show Percentage",
        checked: config.showPercentage
      ),
      WidgetContextMenuItem(
        id: VolumeContextMenuAction.toggleExpandOnHover.id,
        title: "Expand Slider on Hover",
        enabled: capabilities.canSetVolume,
        checked: config.expandToSliderOnHover
      ),
      WidgetContextMenuItem(separator: true),
      WidgetContextMenuItem(
        id: VolumeContextMenuAction.openSoundSettings.id,
        title: "Open Sound Settings"
      ),
    ]
  }
}
