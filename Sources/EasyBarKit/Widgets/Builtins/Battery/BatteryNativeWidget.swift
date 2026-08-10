import Foundation
import IOKit.ps
import SwiftTOMLEdit

/// Native battery widget.
///
/// Responsible for:
/// - reading system state (IOKit)
/// - event handling
/// - snapshot creation
/// - delegating rendering
@MainActor
final class BatteryNativeWidget: NativeWidget {

  let rootID = "builtin_battery"
  let widgetStore: WidgetStore

  var appEventSubscriptions: Set<String> {
    [
      AppEvent.powerSourceChange.rawValue,
      AppEvent.chargingStateChange.rawValue,
      AppEvent.systemWoke.rawValue,
    ]
  }

  private var config: Config.BatteryBuiltinConfig
  private let configSnapshotStore: ConfigSnapshotStore
  private let configPersistence: ConfigPersistence
  private let eventObserver: EasyBarEventObserver
  private var timer: Timer?
  private var isHovered = false
  private lazy var renderer = BatteryRenderer(rootID: rootID)

  struct Snapshot {
    let config: Config.BatteryBuiltinConfig
    let placement: Config.BuiltinWidgetPlacement
    let style: Config.BuiltinWidgetStyle
    let percentage: Int
    let fillFraction: Double
    let charging: Bool
    let charged: Bool
    let finishingCharge: Bool
    let onHold: Bool
    let onExternalPower: Bool
    let text: String
    let colorHex: String?
    let showLabel: Bool
    let isUnavailable: Bool
  }

  /// Creates the native battery widget from an immutable config section.
  init(
    config: Config.BatteryBuiltinConfig,
    widgetStore: WidgetStore,
    configSnapshotStore: ConfigSnapshotStore,
    configPersistence: ConfigPersistence,
    eventHub: EventHub
  ) {
    self.config = config
    self.widgetStore = widgetStore
    self.configSnapshotStore = configSnapshotStore
    self.configPersistence = configPersistence
    self.eventObserver = EasyBarEventObserver(eventHub: eventHub)
  }

  // MARK: - Lifecycle

  /// Starts the widget and battery refresh handling.
  func start() {
    eventObserver.start(
      eventNames: appEventSubscriptions.union([
        WidgetEvent.mouseEntered.rawValue,
        WidgetEvent.mouseExited.rawValue,
        WidgetEvent.contextMenuClicked.rawValue,
      ]),
      widgetTargetIDs: [rootID]
    ) { [weak self] payload in
      guard let self, !self.handleAppEvent(payload) else { return }
      self.handleWidgetEvent(payload)
    }

    timer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
      guard let self else { return }

      Task { @MainActor in
        self.publish()
      }
    }

    publish()
  }

  /// Stops the widget and clears its nodes.
  func stop() {
    eventObserver.stop()
    timer?.invalidate()
    timer = nil
    isHovered = false

    clearNodes()
  }

  // MARK: - Publish

  /// Publishes the current battery snapshot.
  private func publish() {
    let snapshot = readSnapshot()
    var nodes = renderer.makeNodes(snapshot: snapshot)
    let contextMenu = BatteryContextMenu.make(config: config)
    for index in nodes.indices {
      nodes[index].contextMenu = contextMenu
    }
    applyNodes(nodes)
  }
}

// MARK: - Snapshot + Events

extension BatteryNativeWidget {

  /// Reads the current render snapshot from IOKit.
  private func readSnapshot() -> Snapshot {
    let placement = config.placement
    let style = config.style

    guard
      let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
      let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
    else {
      return unavailableSnapshot(config: config, placement: placement, style: style)
    }

    for source in list {
      guard
        let desc = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue()
          as? [String: Any],
        (desc[kIOPSIsPresentKey as String] as? Bool) == true
      else {
        continue
      }

      let current = desc[kIOPSCurrentCapacityKey as String] as? Int ?? 0
      let maximumCapacity = desc[kIOPSMaxCapacityKey as String] as? Int ?? 100
      let percentage =
        maximumCapacity > 0
        ? Int((Double(current) / Double(maximumCapacity)) * 100.0)
        : 0

      let charging = (desc[kIOPSIsChargingKey as String] as? Bool) ?? false
      let charged = (desc[kIOPSIsChargedKey as String] as? Bool) ?? false
      let finishingCharge = (desc[kIOPSIsFinishingChargeKey as String] as? Bool) ?? false
      let onExternalPower =
        (desc[kIOPSPowerSourceStateKey as String] as? String) == kIOPSACPowerValue

      let onHold =
        onExternalPower
        && !charging
        && !charged
        && !finishingCharge
        && percentage < 100

      let clampedPercentage = Swift.max(0, Swift.min(percentage, 100))
      let fillFraction = Double(clampedPercentage) / 100.0
      let text = "\(clampedPercentage)%"

      return Snapshot(
        config: config,
        placement: placement,
        style: style,
        percentage: clampedPercentage,
        fillFraction: fillFraction,
        charging: charging,
        charged: charged,
        finishingCharge: finishingCharge,
        onHold: onHold,
        onExternalPower: onExternalPower,
        text: text,
        colorHex: resolvedBatteryColor(
          for: clampedPercentage,
          mode: config.colorMode,
          fixedColorHex: config.fixedColorHex ?? style.textColorHex,
          colors: config.colors
        ),
        showLabel: shouldShowLabel(config: config, text: text),
        isUnavailable: false
      )
    }

    return unavailableSnapshot(config: config, placement: placement, style: style)
  }

  /// Handles relevant app-wide battery events.
  private func handleAppEvent(_ payload: EasyBarEventPayload) -> Bool {
    guard let event = payload.appEvent else { return false }

    guard
      event == .powerSourceChange
        || event == .chargingStateChange
        || event == .systemWoke
    else {
      return false
    }

    publish()
    return true
  }

  /// Handles hover events for inline expand mode.
  private func handleWidgetEvent(_ payload: EasyBarEventPayload) {
    guard payload.widgetID == rootID else { return }
    guard let event = payload.widgetEvent else { return }
    if event == .contextMenuClicked, let actionID = payload.actionID {
      handleContextMenuAction(actionID)
      return
    }
    guard NativeWidgetHoverSupport.updateHoverState(event, isHovered: &isHovered) else { return }
    publishIfHoverAffectsLayout()
  }

  private func handleContextMenuAction(_ actionID: String) {
    guard let action = BatteryContextMenuAction(id: actionID) else { return }
    var updated = config
    let edit: TOMLEdit
    switch action {
    case .setDisplayMode(let mode):
      updated.displayMode = mode
      edit = .init(
        path: ["builtins", "battery", "content", "display_mode"],
        value: .string(mode.rawValue)
      )
    case .setColorMode(let mode):
      updated.colorMode = mode
      edit = .init(
        path: ["builtins", "battery", "content", "color_mode"],
        value: .string(mode.rawValue)
      )
    case .refresh:
      publish()
      return
    }
    guard configPersistence.apply([edit]) else { return }
    config = updated
    configSnapshotStore.applyBatteryOverride(updated)
    publish()
  }

  /// Returns the unavailable fallback snapshot.
  private func unavailableSnapshot(
    config: Config.BatteryBuiltinConfig,
    placement: Config.BuiltinWidgetPlacement,
    style: Config.BuiltinWidgetStyle
  ) -> Snapshot {
    let text = config.unavailableText

    return Snapshot(
      config: config,
      placement: placement,
      style: style,
      percentage: 0,
      fillFraction: 0,
      charging: false,
      charged: false,
      finishingCharge: false,
      onHold: false,
      onExternalPower: false,
      text: text,
      colorHex: resolvedUnavailableColor(config: config),
      showLabel: shouldShowLabel(config: config, text: text),
      isUnavailable: true
    )
  }
}

// MARK: - Display Decisions

extension BatteryNativeWidget {

  /// Returns true when the label should be visible inline.
  private func shouldShowLabel(
    config: Config.BatteryBuiltinConfig,
    text: String
  ) -> Bool {
    guard !text.isEmpty else { return false }

    switch config.displayMode {
    case .none, .tooltip:
      return false
    case .expand:
      return isHovered
    case .always:
      return true
    }
  }

  /// Hover only affects layout for inline expand mode.
  private func publishIfHoverAffectsLayout() {
    guard config.displayMode == .expand else { return }
    publish()
  }

  /// Resolves the displayed battery color.
  private func resolvedBatteryColor(
    for percentage: Int,
    mode: Config.BuiltinBatteryColorMode,
    fixedColorHex: String?,
    colors: Config.BuiltinBatteryColors
  ) -> String? {
    if mode == .fixed {
      return fixedColorHex
    }

    switch percentage {
    case 70...100:
      return colors.highColorHex
    case 50...69:
      return colors.mediumColorHex
    case 30...49:
      return colors.lowColorHex
    default:
      return colors.criticalColorHex
    }
  }

  /// Resolves the color used when the battery is unavailable.
  private func resolvedUnavailableColor(config: Config.BatteryBuiltinConfig) -> String? {
    return config.colors.unavailableColorHex
  }
}
