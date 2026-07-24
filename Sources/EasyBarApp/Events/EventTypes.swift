import Foundation

/// App-wide events emitted by EasyBar.
enum AppEvent: String, CaseIterable, Sendable {
  case manualRefresh = "manual_refresh"

  case systemWoke = "system_woke"
  case sessionActive = "session_active"
  case sessionInactive = "session_inactive"
  case sleep = "sleep"
  case spaceChange = "space_change"
  case appSwitch = "app_switch"
  case displayChange = "display_change"

  case captureDevicesChanged = "capture_devices_changed"
  case captureActivityChanged = "capture_activity_changed"
  case cameraActivityChanged = "camera_activity_changed"
  case microphoneActivityChanged = "microphone_activity_changed"

  case powerSourceChange = "power_source_change"
  case chargingStateChange = "charging_state_change"

  case networkChange = "network_change"
  case wifiChange = "wifi_change"

  case volumeChange = "volume_change"
  case muteChange = "mute_change"

  case calendarChange = "calendar_change"

  case minuteTick = "minute_tick"
  case secondTick = "second_tick"
  case intervalTick = "interval_tick"

  case focusChange = "focus_change"
  case workspaceChange = "workspace_change"
  case spaceModeChange = "space_mode_change"
}

/// Widget-scoped interaction events emitted by EasyBar.
enum WidgetEvent: String, CaseIterable, Sendable {
  case mouseEntered = "mouse.entered"
  case mouseExited = "mouse.exited"
  case mouseDown = "mouse.down"
  case mouseUp = "mouse.up"
  case mouseClicked = "mouse.clicked"
  case mouseScrolled = "mouse.scrolled"

  case contextMenuClicked = "context_menu.clicked"
  case inboxAction = "inbox.action"
  case inboxContextAction = "inbox.context_action"

  case sliderPreview = "slider.preview"
  case sliderChanged = "slider.changed"
}

/// Mouse button names used by widget interaction events.
enum MouseButton: String, CaseIterable, Sendable {
  case left
  case right
  case middle
}

/// Scroll direction names used by widget interaction events.
enum ScrollDirection: String, CaseIterable, Sendable {
  case up
  case down
  case left
  case right
}

/// Capture-device category exposed to native and Lua event consumers.
enum CaptureDeviceKind: String, Encodable, Hashable, Sendable {
  case camera
  case microphone
}

/// One connected camera or microphone in a capture-device snapshot.
struct CaptureDeviceState: Encodable, Equatable, Sendable {
  let id: String
  let name: String
  let kind: CaptureDeviceKind
  let connected: Bool
  let active: Bool
}

/// Normalized camera and microphone state shared by native and Lua subscribers.
struct CaptureDeviceSnapshot: Encodable, Equatable, Sendable {
  let active: Bool
  let cameraActive: Bool
  let microphoneActive: Bool
  let cameras: [CaptureDeviceState]
  let microphones: [CaptureDeviceState]

  static let empty = CaptureDeviceSnapshot(cameras: [], microphones: [])

  init(cameras: [CaptureDeviceState], microphones: [CaptureDeviceState]) {
    self.cameras = cameras
    self.microphones = microphones
    cameraActive = cameras.contains(where: \.active)
    microphoneActive = microphones.contains(where: \.active)
    active = cameraActive || microphoneActive
  }

  private enum CodingKeys: String, CodingKey {
    case active
    case cameraActive = "camera_active"
    case microphoneActive = "microphone_active"
    case cameras
    case microphones
  }
}

/// Strongly typed event payload used inside Swift.
struct EasyBarEventPayload: Sendable {
  /// App-wide event kind, when this is an app event.
  let appEvent: AppEvent?
  /// Widget-scoped event kind, when this is a widget event.
  let widgetEvent: WidgetEvent?

  /// Source widget identifier.
  let widgetID: String?
  /// Target widget identifier for routed events.
  let targetWidgetID: String?
  /// Frontmost app name associated with the event.
  let appName: String?
  /// Network interface name associated with the event.
  let interfaceName: String?
  /// Mouse button associated with the event.
  let button: MouseButton?
  /// Scroll direction associated with the event.
  let direction: ScrollDirection?
  /// Diagnostic source that caused the event to be emitted.
  let source: String?
  /// Normalized camera and microphone state associated with capture events.
  let capture: CaptureDeviceSnapshot?

  /// Charging state associated with the event.
  let charging: Bool?
  /// Mute state associated with the event.
  let muted: Bool?
  /// Whether the primary network interface is a tunnel.
  let primaryInterfaceIsTunnel: Bool?

  /// Numeric value associated with the event.
  let value: Double?
  /// Horizontal scroll delta.
  let deltaX: Double?
  /// Vertical scroll delta.
  let deltaY: Double?
  /// Selected native context-menu action identifier.
  let actionID: String?

  // MARK: - Builders

  /// Builds an app-wide event payload.
  static func app(
    _ event: AppEvent,
    widgetID: String? = nil,
    appName: String? = nil,
    interfaceName: String? = nil,
    source: String? = nil,
    capture: CaptureDeviceSnapshot? = nil,
    charging: Bool? = nil,
    muted: Bool? = nil,
    primaryInterfaceIsTunnel: Bool? = nil
  ) -> EasyBarEventPayload {
    makePayload(
      appEvent: event,
      widgetID: widgetID,
      appName: appName,
      interfaceName: interfaceName,
      source: source,
      capture: capture,
      charging: charging,
      muted: muted,
      primaryInterfaceIsTunnel: primaryInterfaceIsTunnel
    )
  }

  /// Builds a widget-scoped event payload.
  static func widget(
    _ event: WidgetEvent,
    widgetID: String,
    targetWidgetID: String? = nil,
    source: String? = nil,
    button: MouseButton? = nil,
    direction: ScrollDirection? = nil,
    value: Double? = nil,
    deltaX: Double? = nil,
    deltaY: Double? = nil,
    actionID: String? = nil
  ) -> EasyBarEventPayload {
    makePayload(
      widgetEvent: event,
      widgetID: widgetID,
      targetWidgetID: targetWidgetID,
      source: source,
      button: button,
      direction: direction,
      value: value,
      deltaX: deltaX,
      deltaY: deltaY,
      actionID: actionID
    )
  }

  // MARK: - Public

  /// Runtime event name.
  var eventName: String {
    return appEvent?.rawValue ?? widgetEvent?.rawValue ?? ""
  }

  /// Public event name sent across the Lua runtime boundary.
  var luaEventName: String {
    if appEvent == .manualRefresh {
      return EventCatalog.forcedEventName
    }
    return eventName
  }

  /// Structured payload sent to Lua.
  var luaPayload: LuaEventPayload {
    LuaEventPayload(
      name: luaEventName,
      widgetID: widgetID,
      targetWidgetID: targetWidgetID,
      source: source,
      button: button?.rawValue,
      direction: direction?.rawValue,
      value: value,
      deltaX: deltaX,
      deltaY: deltaY,
      actionID: actionID,
      capture: capture,
      network: hasNetworkPayload
        ? .init(
          primaryInterfaceIsTunnel: primaryInterfaceIsTunnel,
          interfaceName: interfaceName
        )
        : nil,
      power: charging.map { .init(charging: $0) },
      audio: hasAudioPayload
        ? .init(
          muted: muted,
          value: value
        )
        : nil,
      appName: appName
    )
  }

  // MARK: - Internal

  /// Creates one event payload from optional app or widget context.
  private static func makePayload(
    appEvent: AppEvent? = nil,
    widgetEvent: WidgetEvent? = nil,
    widgetID: String? = nil,
    targetWidgetID: String? = nil,
    appName: String? = nil,
    interfaceName: String? = nil,
    source: String? = nil,
    capture: CaptureDeviceSnapshot? = nil,
    button: MouseButton? = nil,
    direction: ScrollDirection? = nil,
    charging: Bool? = nil,
    muted: Bool? = nil,
    primaryInterfaceIsTunnel: Bool? = nil,
    value: Double? = nil,
    deltaX: Double? = nil,
    deltaY: Double? = nil,
    actionID: String? = nil
  ) -> EasyBarEventPayload {
    EasyBarEventPayload(
      appEvent: appEvent,
      widgetEvent: widgetEvent,
      widgetID: widgetID,
      targetWidgetID: targetWidgetID,
      appName: appName,
      interfaceName: interfaceName,
      button: button,
      direction: direction,
      source: source,
      capture: capture,
      charging: charging,
      muted: muted,
      primaryInterfaceIsTunnel: primaryInterfaceIsTunnel,
      value: value,
      deltaX: deltaX,
      deltaY: deltaY,
      actionID: actionID
    )
  }

  /// Returns whether the payload should include the nested network block.
  private var hasNetworkPayload: Bool {
    return primaryInterfaceIsTunnel != nil || interfaceName != nil
  }

  /// Returns whether the payload should include the nested audio block.
  private var hasAudioPayload: Bool {
    return muted != nil || value != nil
  }
}

/// Codable event payload shape delivered to Lua.
struct LuaEventPayload: Encodable, Equatable, Sendable {
  struct Network: Encodable, Equatable, Sendable {
    let primaryInterfaceIsTunnel: Bool?
    let interfaceName: String?

    private enum CodingKeys: String, CodingKey {
      case primaryInterfaceIsTunnel = "primary_interface_is_tunnel"
      case interfaceName = "interface_name"
    }
  }

  struct Power: Encodable, Equatable, Sendable {
    let charging: Bool
  }

  struct Audio: Encodable, Equatable, Sendable {
    let muted: Bool?
    let value: Double?
  }

  let name: String
  let widgetID: String?
  let targetWidgetID: String?
  let source: String?
  let button: String?
  let direction: String?
  let value: Double?
  let deltaX: Double?
  let deltaY: Double?
  let actionID: String?
  let capture: CaptureDeviceSnapshot?
  let network: Network?
  let power: Power?
  let audio: Audio?
  let appName: String?

  private enum CodingKeys: String, CodingKey {
    case name
    case widgetID = "widget_id"
    case targetWidgetID = "target_widget_id"
    case source
    case button
    case direction
    case value
    case deltaX = "delta_x"
    case deltaY = "delta_y"
    case actionID = "action_id"
    case capture
    case network
    case power
    case audio
    case appName = "app_name"
  }
}
