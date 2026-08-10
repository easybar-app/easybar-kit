import EasyBarShared
import Foundation
import SwiftTOMLEdit

/// Internal registry for EasyBarKit-owned built-in surfaces.
///
/// This is not a public Swift widget extension point; third-party widgets are Lua packages.
@MainActor
final class NativeWidgetRegistry {
  private struct Registration {
    let id: String
    let enabled: Bool
    let makeWidget: () -> NativeWidget
  }

  private let logger: ProcessLogger
  private let builtInSurfacePolicy: EasyBarBuiltInSurfacePolicy
  private let widgetStore: WidgetStore
  private let configSnapshotStore: ConfigSnapshotStore
  private let configPersistence: ConfigPersistence
  private let eventManager: EventManager
  private let eventHub: EventHub
  private let contextMenuObserver: EasyBarEventObserver
  private let aeroSpaceService: AeroSpaceService
  private let networkAgentClient: NetworkAgentClient
  private let nativeWiFiStore: NativeWiFiStore
  private let nativeUpcomingCalendarStore: NativeUpcomingCalendarStore
  private let nativeMonthCalendarStore: NativeMonthCalendarStore
  private let nativeComposerCalendarStore: NativeComposerCalendarStore
  private let inboxStore: InboxStore
  private let upcomingCalendarAgentClient: UpcomingCalendarAgentClient
  private let monthCalendarAgentClient: MonthCalendarAgentClient
  private var snapshot: ConfigSnapshot
  private var widgets: [NativeWidget] = []
  private var groupRootIDs: [String] = []

  init(
    logger: ProcessLogger,
    snapshot: ConfigSnapshot,
    builtInSurfacePolicy: EasyBarBuiltInSurfacePolicy,
    widgetStore: WidgetStore,
    configSnapshotStore: ConfigSnapshotStore,
    eventManager: EventManager,
    eventHub: EventHub,
    aeroSpaceService: AeroSpaceService,
    networkAgentClient: NetworkAgentClient,
    nativeWiFiStore: NativeWiFiStore,
    nativeUpcomingCalendarStore: NativeUpcomingCalendarStore,
    nativeMonthCalendarStore: NativeMonthCalendarStore,
    nativeComposerCalendarStore: NativeComposerCalendarStore,
    inboxStore: InboxStore,
    upcomingCalendarAgentClient: UpcomingCalendarAgentClient,
    monthCalendarAgentClient: MonthCalendarAgentClient
  ) {
    self.logger = logger
    self.snapshot = snapshot
    self.builtInSurfacePolicy = builtInSurfacePolicy
    self.widgetStore = widgetStore
    self.configSnapshotStore = configSnapshotStore
    self.configPersistence = ConfigPersistence(
      configPath: snapshot.app.configPath,
      logger: logger.child("config_persistence")
    )
    self.eventManager = eventManager
    self.eventHub = eventHub
    self.contextMenuObserver = EasyBarEventObserver(eventHub: eventHub)
    self.aeroSpaceService = aeroSpaceService
    self.networkAgentClient = networkAgentClient
    self.nativeWiFiStore = nativeWiFiStore
    self.nativeUpcomingCalendarStore = nativeUpcomingCalendarStore
    self.nativeMonthCalendarStore = nativeMonthCalendarStore
    self.nativeComposerCalendarStore = nativeComposerCalendarStore
    self.inboxStore = inboxStore
    self.upcomingCalendarAgentClient = upcomingCalendarAgentClient
    self.monthCalendarAgentClient = monthCalendarAgentClient
  }

  /// Starts all enabled built-in surfaces allowed by the frontend policy.
  func start(snapshot: ConfigSnapshot? = nil) {
    if let snapshot {
      self.snapshot = snapshot
    }

    registerAll()
  }

  /// Rebuilds the built-in surface list from an immutable config snapshot.
  func reload(snapshot: ConfigSnapshot) {
    self.snapshot = snapshot
    registerAll()
  }

  /// Stops all built-in surfaces.
  func stop() {
    stopAll()
  }

  /// Registers all enabled built-in surfaces allowed by the frontend.
  private func registerAll() {
    logger.debug(
      "built-in surface registry registerAll begin",
      .field("policy", builtInSurfacePolicy.rawValue)
    )

    stopAll()

    let registrations = registrations().filter { builtInSurfacePolicy.allows($0.id) }

    logger.debug("registering built-in surfaces")
    logger.debug(
      "built-in surface config",
      .field(
        "surfaces",
        registrations.map { "\($0.id)=\($0.enabled)" }.joined(separator: ",")
      ),
      .field("calendar_popup_mode", snapshot.builtins.calendar.popupMode.rawValue),
    )

    if builtInSurfacePolicy == .all {
      publishGroups(snapshot.builtins.groups)
    } else {
      clearGroups()
    }
    widgets = registrations.filter(\.enabled).map { $0.makeWidget() }

    logger.debug(
      "built-in surfaces registered",
      .field("count", widgets.count),
      .field("ids", widgets.map(\.rootID).joined(separator: ",")),
    )

    let subscriptions = widgets.reduce(into: Set<String>()) { result, widget in
      result.formUnion(widget.appEventSubscriptions)
    }
    logger.debug(
      "built-in surface event subscriptions",
      .field("subscriptions", subscriptions),
    )
    eventManager.setNativeSubscriptions(subscriptions)

    for widget in widgets {
      logger.debug(
        "starting built-in surface",
        .field("runtime", "native"),
        .field("widget", widget.rootID)
      )
      widget.start()
    }

    observeCommonContextMenuActions()

    logger.debug("built-in surface registry registerAll end")
  }

  /// Stops and clears all widgets.
  private func stopAll() {
    contextMenuObserver.stop()
    if !widgets.isEmpty {
      logger.debug(
        "built-in surface registry stopping",
        .field("count", widgets.count),
      )
    }

    for widget in widgets {
      logger.debug(
        "stopping built-in surface",
        .field("runtime", "native"),
        .field("widget", widget.rootID),
      )
      widget.stop()
    }

    widgets.removeAll()
    eventManager.setNativeSubscriptions([])
    clearGroups()
  }

  /// Observes controls that are present in every native widget context menu.
  private func observeCommonContextMenuActions() {
    contextMenuObserver.start(
      eventNames: [WidgetEvent.contextMenuClicked.rawValue],
      widgetTargetIDs: Set(widgets.map(\.rootID))
    ) { [weak self] payload in
      guard
        let self,
        let rootID = payload.widgetID,
        let actionID = payload.actionID,
        let action = NativeWidgetContextMenuAction(rawValue: actionID)
      else { return }

      switch action {
      case .reload:
        self.widgets.first(where: { $0.rootID == rootID })?.reload()
      case .disable:
        self.disableWidget(rootID: rootID)
      }
    }
  }

  /// Persists a disabled widget and removes it from the running registry immediately.
  private func disableWidget(rootID: String) {
    guard let key = Self.configKeyByRootID[rootID] else { return }
    guard
      configPersistence.apply([
        TOMLEdit(path: ["builtins", key, "enabled"], value: .bool(false))
      ])
    else { return }

    configSnapshotStore.applyNativeWidgetEnabledOverride(key, enabled: false)
    guard let index = widgets.firstIndex(where: { $0.rootID == rootID }) else { return }
    widgets.remove(at: index).stop()
    eventManager.setNativeSubscriptions(
      widgets.reduce(into: Set<String>()) { result, widget in
        result.formUnion(widget.appEventSubscriptions)
      }
    )
    observeCommonContextMenuActions()
  }

  private static let configKeyByRootID = [
    "builtin_inbox": "inbox",
    "builtin_privacy_spacer": "privacy_spacer",
    "builtin_spaces": "spaces",
    "builtin_battery": "battery",
    "builtin_front_app": "front_app",
    "builtin_aerospace_mode": "aerospace_mode",
    "builtin_volume": "volume",
    "builtin_wifi": "wifi",
    "builtin_date": "date",
    "builtin_time": "time",
    "builtin_calendar": "calendar",
    "builtin_cpu": "cpu",
  ]

  private func publishGroups(_ groups: [Config.BuiltinGroupConfig]) {
    clearGroups()

    for group in groups {
      widgetStore.apply(
        owner: .native(root: group.id),
        nodes: [
          BuiltinNativeNodeFactory.makeGroupNode(
            id: group.id,
            placement: group.placement,
            style: group.style
          )
        ]
      )
      groupRootIDs.append(group.id)
    }
  }

  private func clearGroups() {
    for rootID in groupRootIDs {
      widgetStore.apply(owner: .native(root: rootID), nodes: [])
    }
    groupRootIDs.removeAll()
  }

  /// Returns the built-in surface registration list for the current config snapshot.
  private func registrations() -> [Registration] {
    let snapshot = self.snapshot
    let builtins = snapshot.builtins
    let networkAgent = snapshot.networkAgent
    let calendarAgent = snapshot.calendarAgent

    var registrations = [
      Registration(id: "inbox", enabled: builtins.inbox.enabled) {
        InboxNativeWidget(
          config: builtins.inbox,
          widgetStore: self.widgetStore,
          inboxStore: self.inboxStore,
          configSnapshotStore: self.configSnapshotStore,
          configPersistence: self.configPersistence,
          eventHub: self.eventHub
        )
      },
      Registration(id: "privacy_spacer", enabled: builtins.privacySpacer.enabled) {
        SpacerNativeWidget(
          rootID: "builtin_privacy_spacer",
          config: builtins.privacySpacer,
          widgetStore: self.widgetStore
        )
      },
      Registration(id: "spaces", enabled: builtins.spaces.enabled) {
        SpacesNativeWidget(
          config: builtins.spaces,
          widgetStore: self.widgetStore,
          aeroSpaceService: self.aeroSpaceService
        )
      },
      Registration(id: "battery", enabled: builtins.battery.enabled) {
        BatteryNativeWidget(
          config: builtins.battery,
          widgetStore: self.widgetStore,
          configSnapshotStore: self.configSnapshotStore,
          configPersistence: self.configPersistence,
          eventHub: self.eventHub
        )
      },
      Registration(id: "front_app", enabled: builtins.frontApp.enabled) {
        FrontAppNativeWidget(
          config: builtins.frontApp,
          widgetStore: self.widgetStore,
          configSnapshotStore: self.configSnapshotStore,
          configPersistence: self.configPersistence,
          eventHub: self.eventHub,
          aeroSpaceService: self.aeroSpaceService
        )
      },
      Registration(id: "aerospace_mode", enabled: builtins.aerospaceMode.enabled) {
        AeroSpaceModeNativeWidget(
          config: builtins.aerospaceMode,
          widgetStore: self.widgetStore,
          configSnapshotStore: self.configSnapshotStore,
          configPersistence: self.configPersistence,
          eventHub: self.eventHub,
          aeroSpaceService: self.aeroSpaceService
        )
      },
      Registration(id: "volume", enabled: builtins.volume.enabled) {
        VolumeSliderNativeWidget(
          config: builtins.volume,
          widgetStore: self.widgetStore,
          configSnapshotStore: self.configSnapshotStore,
          configPersistence: self.configPersistence,
          eventHub: self.eventHub,
          logger: self.logger.child("volume")
        )
      },
      Registration(id: "wifi", enabled: builtins.wifi.enabled) {
        WiFiNativeWidget(
          config: builtins.wifi,
          networkAgentConfig: networkAgent,
          widgetStore: self.widgetStore,
          networkAgentClient: self.networkAgentClient,
          nativeWiFiStore: self.nativeWiFiStore,
          configPersistence: self.configPersistence,
          eventHub: self.eventHub
        )
      },
      Registration(id: "date", enabled: builtins.date.placement.enabled) {
        FormattedClockNativeWidget(
          rootID: "builtin_date",
          widgetStore: self.widgetStore,
          eventHub: self.eventHub,
          placement: builtins.date.placement,
          style: builtins.date.style,
          format: builtins.date.content.format
        )
      },
      Registration(id: "time", enabled: builtins.time.placement.enabled) {
        FormattedClockNativeWidget(
          rootID: "builtin_time",
          widgetStore: self.widgetStore,
          eventHub: self.eventHub,
          placement: builtins.time.placement,
          style: builtins.time.style,
          format: builtins.time.content.format
        )
      },
      Registration(id: "calendar", enabled: builtins.calendar.enabled) {
        CalendarNativeWidget(
          config: builtins.calendar,
          calendarAgentConfig: calendarAgent,
          widgetStore: self.widgetStore,
          configSnapshotStore: self.configSnapshotStore,
          configPersistence: self.configPersistence,
          nativeUpcomingCalendarStore: self.nativeUpcomingCalendarStore,
          nativeMonthCalendarStore: self.nativeMonthCalendarStore,
          nativeComposerCalendarStore: self.nativeComposerCalendarStore,
          upcomingCalendarAgentClient: self.upcomingCalendarAgentClient,
          monthCalendarAgentClient: self.monthCalendarAgentClient,
          eventHub: self.eventHub
        )
      },
      Registration(id: "cpu", enabled: builtins.cpu.enabled) {
        CPUSparklineNativeWidget(
          config: builtins.cpu,
          widgetStore: self.widgetStore,
          configSnapshotStore: self.configSnapshotStore,
          configPersistence: self.configPersistence,
          eventHub: self.eventHub,
          logger: self.logger.child("cpu")
        )
      },
    ]

    registrations.insert(
      contentsOf: builtins.spacers.map { spacer in
        let rootID = "builtin_spacer:\(spacer.id)"
        return Registration(id: "spacer.\(spacer.id)", enabled: spacer.config.enabled) {
          SpacerNativeWidget(
            rootID: rootID,
            config: spacer.config,
            widgetStore: self.widgetStore
          )
        }
      },
      at: 2
    )

    return registrations
  }

}
