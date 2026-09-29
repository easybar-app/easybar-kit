import EasyBarShared
import Foundation

/// Explicitly owned app services used by the app shell and runtime coordinator.
struct AppServices: @unchecked Sendable {
  /// The config for this app services.
  let config: Config
  /// The config manager for this app services.
  let configManager: ConfigManager
  /// The config snapshot store for this app services.
  let configSnapshotStore: ConfigSnapshotStore
  /// The Lua runtime for this app services.
  let luaRuntime: LuaRuntime
  /// The event hub for this app services.
  let eventHub: EventHub
  /// The event manager for this app services.
  let eventManager: EventManager
  /// The capture device events for this app services.
  let captureDeviceEvents: CaptureDeviceEvents
  /// The system events for this app services.
  let systemEvents: SystemEvents
  /// The power events for this app services.
  let powerEvents: PowerEvents
  /// The timer events for this app services.
  let timerEvents: TimerEvents
  /// The volume events for this app services.
  let volumeEvents: VolumeEvents
  /// The widget store for this app services.
  let widgetStore: WidgetStore
  /// The native widget registry for this app services.
  let nativeWidgetRegistry: NativeWidgetRegistry
  /// The inbox store for this app services.
  let inboxStore: InboxStore
  /// The AeroSpace service for this app services.
  let aeroSpaceService: AeroSpaceService
  /// The calendar agent event relay for this app services.
  let calendarAgentEventRelay: CalendarAgentEventRelay
  /// The network agent client for this app services.
  let networkAgentClient: NetworkAgentClient
  /// The native Wi-Fi store for this app services.
  let nativeWiFiStore: NativeWiFiStore
  /// The native month calendar store for this app services.
  let nativeMonthCalendarStore: NativeMonthCalendarStore
  /// The native upcoming calendar store for this app services.
  let nativeUpcomingCalendarStore: NativeUpcomingCalendarStore
  /// The native composer calendar store for this app services.
  let nativeComposerCalendarStore: NativeComposerCalendarStore
  /// The month calendar agent client for this app services.
  let monthCalendarAgentClient: MonthCalendarAgentClient
  /// The upcoming calendar agent client for this app services.
  let upcomingCalendarAgentClient: UpcomingCalendarAgentClient
  /// The composer calendar agent client for this app services.
  let composerCalendarAgentClient: ComposerCalendarAgentClient
  /// The metrics coordinator for this app services.
  let metricsCoordinator: MetricsCoordinator

  @MainActor
  /// Bootstraps the application services.
  static func bootstrap(
    logger: ProcessLogger,
    builtInSurfacePolicy: EasyBarBuiltInSurfacePolicy = .all,
    cliName: String = "easybar"
  ) -> AppServices {
    let config = Config.makeUnloadedConfig(builtInSurfacePolicy: builtInSurfacePolicy)
    let bootstrapSnapshot = config.snapshot()
    let configSnapshotStore = ConfigSnapshotStore(
      snapshot: bootstrapSnapshot,
      snapshotDidChange: { config.apply($0) }
    )
    let configManager = ConfigManager(config: config)
    let metricsCoordinator = MetricsCoordinator.shared
    let inboxStateURL = URL(
      fileURLWithPath: bootstrapSnapshot.app.runtimeDirectory,
      isDirectory: true
    ).appendingPathComponent("inbox-state.json")
    let inboxStore = InboxStore(
      configuration: bootstrapSnapshot.builtins.inbox,
      stateURL: inboxStateURL,
      logger: logger.child("inbox")
    )
    let nativeWiFiStore = NativeWiFiStore(logger: logger.child("wifi_store"))
    let nativeMonthCalendarStore = NativeMonthCalendarStore(logger: logger.child("month_store"))
    let nativeUpcomingCalendarStore = NativeUpcomingCalendarStore(
      logger: logger.child("upcoming_store")
    )
    let nativeComposerCalendarStore = NativeComposerCalendarStore(
      logger: logger.child("composer_calendar_store")
    )
    let luaRuntime = LuaRuntime(
      logger: logger.child("lua"),
      metricsCoordinator: metricsCoordinator,
      cliName: cliName
    )
    let eventLogger = logger.child("events")
    let eventHub = EventHub(
      logger: eventLogger.child("hub"),
      luaRuntime: luaRuntime,
      metricsCoordinator: metricsCoordinator,
      wifiSnapshotProvider: { nativeWiFiStore.snapshot }
    )
    let captureDeviceEvents = CaptureDeviceEvents(
      logger: eventLogger.child("capture"),
      eventHub: eventHub
    )
    let systemEvents = SystemEvents(logger: eventLogger.child("system"), eventHub: eventHub)
    let powerEvents = PowerEvents(logger: eventLogger.child("power"), eventHub: eventHub)
    let timerEvents = TimerEvents(logger: eventLogger.child("timer"), eventHub: eventHub)
    let volumeEvents = VolumeEvents(logger: eventLogger.child("volume"), eventHub: eventHub)
    let eventManager = EventManager(
      logger: eventLogger.child("manager"),
      systemEvents: systemEvents,
      powerEvents: powerEvents,
      timerEvents: timerEvents,
      volumeEvents: volumeEvents,
      captureDeviceEvents: captureDeviceEvents
    )
    let agentServices = makeAgentServices(
      logger: logger,
      snapshot: bootstrapSnapshot,
      metricsCoordinator: metricsCoordinator,
      eventHub: eventHub,
      nativeWiFiStore: nativeWiFiStore,
      nativeMonthCalendarStore: nativeMonthCalendarStore,
      nativeUpcomingCalendarStore: nativeUpcomingCalendarStore,
      nativeComposerCalendarStore: nativeComposerCalendarStore
    )
    let nativeServices = makeNativeServices(
      logger: logger,
      snapshot: bootstrapSnapshot,
      builtInSurfacePolicy: builtInSurfacePolicy,
      configSnapshotStore: configSnapshotStore,
      eventManager: eventManager,
      eventHub: eventHub,
      nativeWiFiStore: nativeWiFiStore,
      nativeMonthCalendarStore: nativeMonthCalendarStore,
      nativeUpcomingCalendarStore: nativeUpcomingCalendarStore,
      nativeComposerCalendarStore: nativeComposerCalendarStore,
      inboxStore: inboxStore,
      agentServices: agentServices
    )

    let services = AppServices(
      config: config,
      configManager: configManager,
      configSnapshotStore: configSnapshotStore,
      luaRuntime: luaRuntime,
      eventHub: eventHub,
      eventManager: eventManager,
      captureDeviceEvents: captureDeviceEvents,
      systemEvents: systemEvents,
      powerEvents: powerEvents,
      timerEvents: timerEvents,
      volumeEvents: volumeEvents,
      widgetStore: nativeServices.widgetStore,
      nativeWidgetRegistry: nativeServices.nativeWidgetRegistry,
      inboxStore: inboxStore,
      aeroSpaceService: nativeServices.aeroSpaceService,
      calendarAgentEventRelay: agentServices.calendarAgentEventRelay,
      networkAgentClient: agentServices.networkAgentClient,
      nativeWiFiStore: nativeServices.nativeWiFiStore,
      nativeMonthCalendarStore: nativeServices.nativeMonthCalendarStore,
      nativeUpcomingCalendarStore: nativeServices.nativeUpcomingCalendarStore,
      nativeComposerCalendarStore: nativeServices.nativeComposerCalendarStore,
      monthCalendarAgentClient: agentServices.monthCalendarAgentClient,
      upcomingCalendarAgentClient: agentServices.upcomingCalendarAgentClient,
      composerCalendarAgentClient: agentServices.composerCalendarAgentClient,
      metricsCoordinator: metricsCoordinator
    )

    return services
  }

  @MainActor
  /// Applies runtime configuration.
  func applyRuntimeConfiguration(_ snapshot: ConfigSnapshot) {
    configSnapshotStore.apply(snapshot)
    inboxStore.updateStateURL(
      URL(fileURLWithPath: snapshot.app.runtimeDirectory, isDirectory: true)
        .appendingPathComponent("inbox-state.json")
    )
    networkAgentClient.updateConfiguration(snapshot.networkAgent)
    monthCalendarAgentClient.updateConfiguration(
      calendarAgentConfig: snapshot.calendarAgent,
      calendarConfig: snapshot.builtins.calendar
    )
    upcomingCalendarAgentClient.updateConfiguration(
      calendarAgentConfig: snapshot.calendarAgent,
      calendarConfig: snapshot.builtins.calendar
    )
    composerCalendarAgentClient.updateConfiguration(snapshot.calendarAgent)
  }

  @MainActor
  /// Creates native services.
  private static func makeNativeServices(
    logger: ProcessLogger,
    snapshot: ConfigSnapshot,
    builtInSurfacePolicy: EasyBarBuiltInSurfacePolicy,
    configSnapshotStore: ConfigSnapshotStore,
    eventManager: EventManager,
    eventHub: EventHub,
    nativeWiFiStore: NativeWiFiStore,
    nativeMonthCalendarStore: NativeMonthCalendarStore,
    nativeUpcomingCalendarStore: NativeUpcomingCalendarStore,
    nativeComposerCalendarStore: NativeComposerCalendarStore,
    inboxStore: InboxStore,
    agentServices: AgentServices
  )
    -> NativeServices
  {
    let widgetStore = WidgetStore()
    let aeroSpaceService = AeroSpaceService(
      logger: logger.child("aerospace"),
      eventHub: eventHub
    )

    return NativeServices(
      widgetStore: widgetStore,
      nativeWidgetRegistry: NativeWidgetRegistry(
        logger: logger.child("widgets"),
        snapshot: snapshot,
        builtInSurfacePolicy: builtInSurfacePolicy,
        widgetStore: widgetStore,
        configSnapshotStore: configSnapshotStore,
        eventManager: eventManager,
        eventHub: eventHub,
        aeroSpaceService: aeroSpaceService,
        networkAgentClient: agentServices.networkAgentClient,
        nativeWiFiStore: nativeWiFiStore,
        nativeUpcomingCalendarStore: nativeUpcomingCalendarStore,
        nativeMonthCalendarStore: nativeMonthCalendarStore,
        nativeComposerCalendarStore: nativeComposerCalendarStore,
        inboxStore: inboxStore,
        upcomingCalendarAgentClient: agentServices.upcomingCalendarAgentClient,
        monthCalendarAgentClient: agentServices.monthCalendarAgentClient
      ),
      aeroSpaceService: aeroSpaceService,
      nativeWiFiStore: nativeWiFiStore,
      nativeMonthCalendarStore: nativeMonthCalendarStore,
      nativeUpcomingCalendarStore: nativeUpcomingCalendarStore,
      nativeComposerCalendarStore: nativeComposerCalendarStore
    )
  }

  @MainActor
  /// Creates agent services.
  private static func makeAgentServices(
    logger: ProcessLogger,
    snapshot: ConfigSnapshot,
    metricsCoordinator: MetricsCoordinator,
    eventHub: EventHub,
    nativeWiFiStore: NativeWiFiStore,
    nativeMonthCalendarStore: NativeMonthCalendarStore,
    nativeUpcomingCalendarStore: NativeUpcomingCalendarStore,
    nativeComposerCalendarStore: NativeComposerCalendarStore
  )
    -> AgentServices
  {
    let eventRelay = CalendarAgentEventRelay(
      logger: logger.child("calendar_relay"),
      eventHub: eventHub
    )
    let upcomingClient = UpcomingCalendarAgentClient(
      logger: logger.child("upcoming_agent"),
      calendarAgentConfig: snapshot.calendarAgent,
      calendarConfig: snapshot.builtins.calendar,
      store: nativeUpcomingCalendarStore,
      eventRelay: eventRelay,
      metricsCoordinator: metricsCoordinator
    )
    let composerClient = ComposerCalendarAgentClient(
      logger: logger.child("composer_calendar_agent"),
      calendarAgentConfig: snapshot.calendarAgent,
      store: nativeComposerCalendarStore
    )
    let monthClient = MonthCalendarAgentClient(
      logger: logger.child("month_agent"),
      calendarAgentConfig: snapshot.calendarAgent,
      calendarConfig: snapshot.builtins.calendar,
      store: nativeMonthCalendarStore,
      eventRelay: eventRelay,
      metricsCoordinator: metricsCoordinator
    )
    monthClient.setRelatedClientRefresh {
      upcomingClient.refresh()
      composerClient.refresh()
    }

    return AgentServices(
      calendarAgentEventRelay: eventRelay,
      networkAgentClient: NetworkAgentClient(
        logger: logger.child("network_agent"),
        config: snapshot.networkAgent,
        nativeWiFiStore: nativeWiFiStore,
        eventHub: eventHub,
        metricsCoordinator: metricsCoordinator
      ),
      monthCalendarAgentClient: monthClient,
      upcomingCalendarAgentClient: upcomingClient,
      composerCalendarAgentClient: composerClient
    )
  }
}

/// UI-facing services and stores for host-owned built-in surfaces.
private struct NativeServices {
  /// The widget store for this native services.
  let widgetStore: WidgetStore
  /// The native widget registry for this native services.
  let nativeWidgetRegistry: NativeWidgetRegistry
  /// The AeroSpace service for this native services.
  let aeroSpaceService: AeroSpaceService
  /// The native Wi-Fi store for this native services.
  let nativeWiFiStore: NativeWiFiStore
  /// The native month calendar store for this native services.
  let nativeMonthCalendarStore: NativeMonthCalendarStore
  /// The native upcoming calendar store for this native services.
  let nativeUpcomingCalendarStore: NativeUpcomingCalendarStore
  /// The native composer calendar store for this native services.
  let nativeComposerCalendarStore: NativeComposerCalendarStore
}

/// Helper-agent clients and relays.
private struct AgentServices {
  /// The calendar agent event relay for this agent services.
  let calendarAgentEventRelay: CalendarAgentEventRelay
  /// The network agent client for this agent services.
  let networkAgentClient: NetworkAgentClient
  /// The month calendar agent client for this agent services.
  let monthCalendarAgentClient: MonthCalendarAgentClient
  /// The upcoming calendar agent client for this agent services.
  let upcomingCalendarAgentClient: UpcomingCalendarAgentClient
  /// The composer calendar agent client for this agent services.
  let composerCalendarAgentClient: ComposerCalendarAgentClient
}
