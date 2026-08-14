import AppKit
import EasyBarCalendarConfig
import Foundation
import SwiftTOMLEdit

/// Native calendar anchor widget.
///
/// Responsible only for:
/// - event handling
/// - agent lifecycle
/// - snapshot creation
/// - delegating rendering
@MainActor
final class CalendarNativeWidget: NativeWidget {

  let rootID = "builtin_calendar"
  let widgetStore: WidgetStore

  var appEventSubscriptions: Set<String> {
    let refreshEvent = Self.refreshEvent(for: configuredConfig)
    return [
      refreshEvent.rawValue,
      AppEvent.systemWoke.rawValue,
      AppEvent.calendarChange.rawValue,
    ]
  }

  private var configuredConfig: Config.CalendarBuiltinConfig
  private let configSnapshotStore: ConfigSnapshotStore
  private let configPersistence: ConfigPersistence
  private let calendarAgentConfig: ConfigSnapshot.CalendarAgent
  private let nativeUpcomingCalendarStore: NativeUpcomingCalendarStore
  private let nativeMonthCalendarStore: NativeMonthCalendarStore
  private let nativeComposerCalendarStore: NativeComposerCalendarStore
  private let upcomingCalendarAgentClient: UpcomingCalendarAgentClient
  private let monthCalendarAgentClient: MonthCalendarAgentClient
  private let eventObserver: EasyBarEventObserver
  private var sessionConfig: Config.CalendarBuiltinConfig
  private lazy var renderer = CalendarRenderer(rootID: rootID)

  private var started = false
  private var startedCalendarAgent = false
  private var startedPopupMode: Config.CalendarPopupMode = .none

  struct Snapshot {
    let config: Config.CalendarBuiltinConfig
    let now: Date
  }

  /// Creates the native calendar widget from immutable config sections.
  init(
    config: Config.CalendarBuiltinConfig,
    calendarAgentConfig: ConfigSnapshot.CalendarAgent,
    widgetStore: WidgetStore,
    configSnapshotStore: ConfigSnapshotStore,
    configPersistence: ConfigPersistence,
    nativeUpcomingCalendarStore: NativeUpcomingCalendarStore,
    nativeMonthCalendarStore: NativeMonthCalendarStore,
    nativeComposerCalendarStore: NativeComposerCalendarStore,
    upcomingCalendarAgentClient: UpcomingCalendarAgentClient,
    monthCalendarAgentClient: MonthCalendarAgentClient,
    eventHub: EventHub
  ) {
    self.configuredConfig = config
    self.configSnapshotStore = configSnapshotStore
    self.configPersistence = configPersistence
    self.calendarAgentConfig = calendarAgentConfig
    self.widgetStore = widgetStore
    self.nativeUpcomingCalendarStore = nativeUpcomingCalendarStore
    self.nativeMonthCalendarStore = nativeMonthCalendarStore
    self.nativeComposerCalendarStore = nativeComposerCalendarStore
    self.upcomingCalendarAgentClient = upcomingCalendarAgentClient
    self.monthCalendarAgentClient = monthCalendarAgentClient
    self.eventObserver = EasyBarEventObserver(eventHub: eventHub)
    self.sessionConfig = config
  }

  // MARK: - Lifecycle

  /// Starts the calendar widget.
  func start() {
    guard !started else { return }
    started = true

    let snapshot = currentSnapshot()

    eventObserver.start(
      eventNames: appEventSubscriptions.union([WidgetEvent.contextMenuClicked.rawValue]),
      widgetTargetIDs: [rootID]
    ) { [weak self] payload in
      guard let self else { return }

      if payload.widgetEvent == .contextMenuClicked,
        payload.widgetID == self.rootID,
        let actionID = payload.actionID
      {
        self.handleContextMenuAction(actionID)
        return
      }

      guard let event = payload.appEvent else { return }

      switch event {
      case Self.refreshEvent(for: self.sessionConfig), .systemWoke, .calendarChange:
        self.publish()
      default:
        break
      }
    }

    startedCalendarAgent = snapshot.config.placement.enabled && calendarAgentConfig.enabled
    startedPopupMode = snapshot.config.popupMode

    if startedCalendarAgent {
      startCalendarAgent(for: snapshot)
    }

    publish()
  }

  /// Stops the calendar widget.
  func stop() {
    guard started else { return }
    started = false

    eventObserver.stop()

    if startedCalendarAgent {
      stopCalendarAgent()
      nativeUpcomingCalendarStore.clear()
      nativeMonthCalendarStore.clear()
      nativeComposerCalendarStore.clear()
    }

    startedCalendarAgent = false
    startedPopupMode = .none

    clearNodes()
  }

  // MARK: - Publish

  /// Publishes the current calendar anchor nodes.
  private func publish() {
    let snapshot = currentSnapshot()
    var nodes = renderer.makeNodes(snapshot: snapshot)
    let contextMenu = CalendarContextMenu.make(config: sessionConfig)
    for index in nodes.indices where nodes[index].id != rootID {
      nodes[index].contextMenu = contextMenu
    }
    applyNodes(nodes)
  }

  // MARK: - Snapshot

  /// Returns the current calendar render snapshot.
  private func currentSnapshot() -> Snapshot {
    Snapshot(
      config: sessionConfig,
      now: Date()
    )
  }

  /// Returns the cheapest tick cadence that keeps the active anchor layout current.
  private static func refreshEvent(for config: Config.CalendarBuiltinConfig) -> AppEvent {
    let needsSecondPrecision = activeFormats(for: config).contains { format in
      FormattedClockRefreshPolicy.event(for: format) == .secondTick
    }
    return needsSecondPrecision ? .secondTick : .minuteTick
  }

  /// Returns only the format strings used by the current anchor layout.
  private static func activeFormats(for config: Config.CalendarBuiltinConfig) -> [String] {
    config.anchor.fields.map { config.anchor.field($0).format }
  }
}

// MARK: - Context Menu

extension CalendarNativeWidget {
  private func handleContextMenuAction(_ actionID: String) {
    guard let action = CalendarContextMenuAction(id: actionID) else { return }

    switch action {
    case .setPopupMode(let mode):
      updatePopupMode(mode)
    case .setAnchorLayout(let layout):
      sessionConfig.anchor.layout = layout
      persistConfiguration()
    case .toggleAnchorField(let field):
      toggleAnchorField(field)
    case .setTodayMarkerVariant(let variant):
      sessionConfig.month.popup.calendar.todayMarkerVariant = variant
      persistConfiguration()
    case .setTodayMarkerSize(let size):
      sessionConfig.month.popup.calendar.todayMarkerSize = Double(size)
      persistConfiguration()
    case .toggleAppointmentOption(let optionID):
      toggleAppointmentOption(optionID)
    case .toggleBirthdayOption(let optionID):
      toggleBirthdayOption(optionID)
    case .refresh:
      refreshActiveCalendarClient()
    case .openCalendarSettings:
      openCalendarSettings()
    }
  }

  private func updatePopupMode(_ mode: CalendarPopupMode) {
    guard sessionConfig.popupMode != mode else { return }

    if startedCalendarAgent {
      stopCalendarAgent()
    }
    sessionConfig.popupMode = mode
    updateAgentConfiguration()
    startedPopupMode = mode
    if startedCalendarAgent {
      startCalendarAgent(for: currentSnapshot())
    }
    persistConfiguration()
  }

  private func toggleAnchorField(_ field: CalendarAnchorFieldKind) {
    if let index = sessionConfig.anchor.fields.firstIndex(of: field) {
      guard sessionConfig.anchor.fields.count > 1 else { return }
      sessionConfig.anchor.fields.remove(at: index)
    } else {
      sessionConfig.anchor.fields.append(field)
    }
    persistConfiguration()
  }

  private func toggleAppointmentOption(_ optionID: String) {
    guard let option = appointmentOptions.first(where: { $0.id == optionID }) else { return }
    sessionConfig.appointments[keyPath: option.keyPath].toggle()
    persistConfiguration()
  }

  private func toggleBirthdayOption(_ optionID: String) {
    guard let option = birthdayOptions.first(where: { $0.id == optionID }) else { return }
    sessionConfig.birthdays[keyPath: option.keyPath].toggle()
    updateAgentConfiguration()
    refreshActiveCalendarClient()
    persistConfiguration()
  }

  private func persistConfiguration() {
    var edits: [TOMLEdit] = [
      TOMLEdit(
        path: ["builtins", "calendar", "popup_mode"],
        value: .string(sessionConfig.popupMode.rawValue)
      ),
      TOMLEdit(
        path: ["builtins", "calendar", "anchor", "layout"],
        value: .string(sessionConfig.anchor.layout.rawValue)
      ),
      TOMLEdit(
        path: ["builtins", "calendar", "anchor", "fields"],
        value: .stringArray(sessionConfig.anchor.fields.map(\.rawValue))
      ),
      TOMLEdit(
        path: ["builtins", "calendar", "month", "popup", "calendar", "today_marker_variant"],
        value: .string(sessionConfig.month.popup.calendar.todayMarkerVariant.rawValue)
      ),
      TOMLEdit(
        path: ["builtins", "calendar", "month", "popup", "calendar", "today_marker_size"],
        value: .double(sessionConfig.month.popup.calendar.todayMarkerSize)
      ),
    ]
    edits.append(
      contentsOf: appointmentOptions.map { option in
        TOMLEdit(
          path: ["builtins", "calendar", "appointments", option.configKey],
          value: .bool(option.value(sessionConfig.appointments))
        )
      }
    )
    edits.append(
      contentsOf: birthdayOptions.map { option in
        TOMLEdit(
          path: ["builtins", "calendar", "birthdays", option.configKey],
          value: .bool(option.value(sessionConfig.birthdays))
        )
      }
    )
    guard configPersistence.apply(edits) else {
      sessionConfig = configuredConfig
      updateAgentConfiguration()
      startedPopupMode = sessionConfig.popupMode
      configSnapshotStore.applyCalendarSessionOverride(configuredConfig)
      publish()
      return
    }
    configuredConfig = sessionConfig
    configSnapshotStore.applyCalendarSessionOverride(sessionConfig)
    publish()
  }

  private func updateAgentConfiguration() {
    upcomingCalendarAgentClient.updateConfiguration(
      calendarAgentConfig: calendarAgentConfig,
      calendarConfig: sessionConfig
    )
    monthCalendarAgentClient.updateConfiguration(
      calendarAgentConfig: calendarAgentConfig,
      calendarConfig: sessionConfig
    )
  }

  private func refreshActiveCalendarClient() {
    switch sessionConfig.popupMode {
    case .none: break
    case .upcoming: upcomingCalendarAgentClient.refresh()
    case .month: monthCalendarAgentClient.refresh()
    }
  }

  private func openCalendarSettings() {
    guard
      let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
      )
    else { return }
    NSWorkspace.shared.open(url)
  }
}

// MARK: - Agent Lifecycle

extension CalendarNativeWidget {

  /// Starts the calendar agent required by the active popup mode.
  private func startCalendarAgent(for snapshot: Snapshot) {
    switch snapshot.config.popupMode {
    case .none:
      break
    case .upcoming:
      upcomingCalendarAgentClient.start()
    case .month:
      monthCalendarAgentClient.start()
      monthCalendarAgentClient.focusVisibleMonth(snapshot.now)
    }
  }

  /// Stops the calendar agent required by the started popup mode.
  private func stopCalendarAgent() {
    switch startedPopupMode {
    case .none:
      break
    case .upcoming:
      upcomingCalendarAgentClient.stop()
    case .month:
      monthCalendarAgentClient.stop()
    }
  }
}
