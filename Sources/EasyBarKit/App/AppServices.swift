import EasyBarShared
import Foundation

/// Explicitly owned app services used by the app shell and runtime coordinator.
struct AppServices: @unchecked Sendable {
  let config: Config
  let configManager: ConfigManager
  let configSnapshotStore: ConfigSnapshotStore
  let luaRuntime: LuaRuntime
  let eventHub: EventHub
  let eventManager: EventManager
  let captureDeviceEvents: CaptureDeviceEvents
  let systemEvents: SystemEvents
  let powerEvents: PowerEvents
  let timerEvents: TimerEvents
  let volumeEvents: VolumeEvents
  let widgetStore: WidgetStore
  let nativeWidgetRegistry: NativeWidgetRegistry
  let inboxStore: InboxStore
  let aeroSpaceService: AeroSpaceService
  let calendarAgentEventRelay: CalendarAgentEventRelay
  let networkAgentClient: NetworkAgentClient
  let nativeWiFiStore: NativeWiFiStore
  let nativeMonthCalendarStore: NativeMonthCalendarStore
  let nativeUpcomingCalendarStore: NativeUpcomingCalendarStore
  let nativeComposerCalendarStore: NativeComposerCalendarStore
  let monthCalendarAgentClient: MonthCalendarAgentClient
  let upcomingCalendarAgentClient: UpcomingCalendarAgentClient
  let composerCalendarAgentClient: ComposerCalendarAgentClient
  let metricsCoordinator: MetricsCoordinator

  @MainActor
  static func bootstrap(
    logger: ProcessLogger,
    builtInSurfacePolicy: EasyBarBuiltInSurfacePolicy = .all
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
      metricsCoordinator: metricsCoordinator
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
  let widgetStore: WidgetStore
  let nativeWidgetRegistry: NativeWidgetRegistry
  let aeroSpaceService: AeroSpaceService
  let nativeWiFiStore: NativeWiFiStore
  let nativeMonthCalendarStore: NativeMonthCalendarStore
  let nativeUpcomingCalendarStore: NativeUpcomingCalendarStore
  let nativeComposerCalendarStore: NativeComposerCalendarStore
}

/// Helper-agent clients and relays.
private struct AgentServices {
  let calendarAgentEventRelay: CalendarAgentEventRelay
  let networkAgentClient: NetworkAgentClient
  let monthCalendarAgentClient: MonthCalendarAgentClient
  let upcomingCalendarAgentClient: UpcomingCalendarAgentClient
  let composerCalendarAgentClient: ComposerCalendarAgentClient
}
