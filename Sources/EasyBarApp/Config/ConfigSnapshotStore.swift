import Foundation

/// Main-actor observable holder for the active immutable config snapshot.
///
/// Runtime services receive explicit `ConfigSnapshot` values. SwiftUI views use this
/// store only to observe which immutable snapshot is currently active.
@MainActor
final class ConfigSnapshotStore: ObservableObject {
  /// Active config snapshot used by UI renderers.
  @Published private(set) var snapshot: ConfigSnapshot
  /// Keeps the authoritative live config synchronized with immediate UI overrides.
  private let snapshotDidChange: (ConfigSnapshot) -> Void

  /// Creates a snapshot store with the provided initial snapshot.
  init(
    snapshot: ConfigSnapshot,
    snapshotDidChange: @escaping (ConfigSnapshot) -> Void = { _ in }
  ) {
    self.snapshot = snapshot
    self.snapshotDidChange = snapshotDidChange
  }

  /// Replaces the active snapshot after a successful or rejected config load.
  func apply(_ snapshot: ConfigSnapshot) {
    self.snapshot = snapshot
    snapshotDidChange(snapshot)
  }

  /// Applies a calendar configuration written by its native context menu.
  func applyCalendarSessionOverride(_ calendar: Config.CalendarBuiltinConfig) {
    updateBuiltins { $0.calendar = calendar }
  }

  /// Applies an inbox configuration written by its native context menu.
  func applyInboxOverride(_ inbox: Config.InboxBuiltinConfig) {
    updateBuiltins { $0.inbox = inbox }
  }

  /// Applies a battery configuration written by its native context menu.
  func applyBatteryOverride(_ battery: Config.BatteryBuiltinConfig) {
    updateBuiltins { $0.battery = battery }
  }

  /// Applies a CPU configuration written by its native context menu.
  func applyCPUOverride(_ cpu: Config.CPUBuiltinConfig) {
    updateBuiltins { $0.cpu = cpu }
  }

  /// Applies a volume configuration written by its native context menu.
  func applyVolumeOverride(_ volume: Config.VolumeBuiltinConfig) {
    updateBuiltins { $0.volume = volume }
  }

  /// Applies a front-app configuration written by its native context menu.
  func applyFrontAppOverride(_ frontApp: Config.FrontAppBuiltinConfig) {
    updateBuiltins { $0.frontApp = frontApp }
  }

  /// Applies an AeroSpace-mode configuration written by its native context menu.
  func applyAeroSpaceModeOverride(_ aerospaceMode: Config.AeroSpaceModeBuiltinConfig) {
    updateBuiltins { $0.aerospaceMode = aerospaceMode }
  }

  /// Updates one top-level native widget's enabled state after context-menu persistence.
  func applyNativeWidgetEnabledOverride(_ key: String, enabled: Bool) {
    let supportedKeys: Set<String> = [
      "inbox", "privacy_spacer", "cpu", "battery", "spaces", "front_app",
      "aerospace_mode", "volume", "wifi", "calendar", "time", "date",
    ]
    guard supportedKeys.contains(key) else { return }

    updateBuiltins { builtins in
      switch key {
      case "inbox": builtins.inbox.placement.enabled = enabled
      case "privacy_spacer": builtins.privacySpacer.placement.enabled = enabled
      case "cpu": builtins.cpu.enabled = enabled
      case "battery": builtins.battery.enabled = enabled
      case "spaces": builtins.spaces.enabled = enabled
      case "front_app": builtins.frontApp.enabled = enabled
      case "aerospace_mode": builtins.aerospaceMode.enabled = enabled
      case "volume": builtins.volume.enabled = enabled
      case "wifi": builtins.wifi.enabled = enabled
      case "calendar": builtins.calendar.enabled = enabled
      case "time": builtins.time.placement.enabled = enabled
      case "date": builtins.date.placement.enabled = enabled
      default: return
      }
    }
  }

  /// Mutates one copy of the built-in config block and republishes a new immutable snapshot.
  private func updateBuiltins(_ update: (inout ConfigSnapshot.Builtins) -> Void) {
    var builtins = snapshot.builtins
    update(&builtins)
    apply(snapshot.replacing(builtins: builtins))
  }
}
