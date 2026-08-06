import AppKit
import EasyBarShared
import Foundation
import SwiftTOMLEdit

/// Main-actor app shell responsible for UI lifecycle and startup wiring.
@MainActor
final class AppController {
  /// Logger used for app-shell diagnostics.
  private let logger: ProcessLogger
  /// Explicit app-wide service graph bootstrapped during startup wiring.
  private let services: AppServices
  /// Coordinates runtime startup, refresh, reload, and shutdown.
  private let runtimeCoordinator: RuntimeCoordinator
  /// Callback used to ask the app delegate to start graceful termination.
  private let requestAppTermination: () -> Void
  /// Logs one-time startup diagnostics for support and troubleshooting.
  private let startupDiagnostics: AppStartupDiagnostics
  /// Installs the generated Lua editor stub for widget authoring.
  private let widgetEditorStubInstaller: WidgetEditorStubInstaller
  /// Converts process signals into graceful termination requests.
  private lazy var signalHandler = AppSignalHandler(logger: logger.child("signals")) {
    [weak self] in
    self?.requestAppTermination()
  }

  /// Whether the app shell has completed startup.
  private var started = false
  /// Shared shutdown task used to avoid duplicate cleanup.
  private var shutdownTask: Task<Void, Never>?
  /// Task that waits for graceful shutdown before terminating AppKit.
  private var terminationRequestTask: Task<Void, Never>?
  /// Controller for the main EasyBar panel.
  private var barWindowController: BarWindowController?
  /// Persistent controller shown in the macOS menu bar.
  private var menuBarController: MenuBarController?
  /// Whether the bar runtime is currently available to user actions.
  private var barRuntimeState = EasyBarRuntimeState.stopped
  /// Serializes user-requested start, stop, and restart transitions.
  private var barLifecycleTask: Task<Void, Never>?
  /// Observer token for runtime config reload completion notifications.
  private var configReloadObserver: NSObjectProtocol?

  /// Presenter for config load errors and non-fatal warnings.
  private let configErrorWindowController = ConfigErrorWindowController()
  /// Prevents multiple EasyBar instances from running at once.
  private let instanceGuard: SingleInstanceGuard

  /// Creates the app shell with its process logger.
  init(
    logger: ProcessLogger,
    requestAppTermination: @escaping () -> Void
  ) {
    let services = AppServices.bootstrap(logger: logger.child("services"))
    let instanceGuard = SingleInstanceGuard()

    self.logger = logger
    self.requestAppTermination = requestAppTermination
    self.services = services
    self.instanceGuard = instanceGuard
    self.runtimeCoordinator = RuntimeCoordinator(
      logger: logger.child("runtime"),
      services: services,
      rebindInstanceLock: { directory in
        AppShellSupport.acquireInstanceLock(
          instanceGuard: instanceGuard,
          processName: "easybar",
          directory: directory,
          logger: logger,
          acquireMessage: "easybar rebound instance lock",
          alreadyRunningMessage: "easybar lock rebind found another running instance",
          failureMessage: "easybar failed to rebind instance lock",
        )
      }
    )
    self.startupDiagnostics = AppStartupDiagnostics(logger: logger.child("diagnostics"))
    self.widgetEditorStubInstaller = WidgetEditorStubInstaller(logger: logger.child("editor_stub"))
  }

  /// Starts the app shell and the actor-owned runtime.
  @discardableResult
  func start() -> Bool {
    guard !started else {
      logger.debug("AppController.start skipped because app is already started")
      return true
    }

    started = true

    let initialConfigError = services.config.loadInitialState()
    configureLogging()
    logger.debug("process logging configured")

    if let error = initialConfigError {
      logger.error(
        "initial config load failed",
        .field("config_path", services.config.configPath),
        .field("error", "\(error)")
      )
    } else {
      logger.info(
        "initial config loaded",
        .field("config_path", services.config.configPath)
      )
    }

    logger.debug("applying runtime configuration")
    services.applyRuntimeConfiguration(services.config.snapshot())

    guard acquireInstanceLock() else {
      started = false
      return false
    }

    NSApp.setActivationPolicy(.accessory)
    logger.debug("activation policy set to accessory")

    startupDiagnostics.logStartup(services: services)
    startupDiagnostics.validateRequiredFonts()
    installWidgetEditorStub()

    let menuStateProvider = makeMenuStateProvider()
    let menuFactory = makeMenuFactory(stateProvider: menuStateProvider)
    setupBarWindowController(menuFactory: menuFactory)
    setupMenuBarController(menuFactory: menuFactory)
    logger.debug("bar window presented")

    installConfigReloadObserver()
    updateConfigIssueWindow()
    signalHandler.start()
    logger.debug("signal handler started")

    runBarLifecycleTransition(finalState: .running) { [weak self] in
      await self?.runtimeCoordinator.start()
    }
    logger.debug("runtime coordinator start scheduled")

    return true
  }

  /// Acquires the single-instance lock for the main EasyBar process.
  private func acquireInstanceLock() -> Bool {
    AppShellSupport.acquireInstanceLock(
      instanceGuard: instanceGuard,
      processName: "easybar",
      directory: services.config.lockDirectory,
      logger: logger,
      acquireMessage: "easybar acquired instance lock",
      alreadyRunningMessage: "easybar already running",
      failureMessage: "easybar failed to acquire instance lock",
    )
  }

  /// Stops the actor-owned runtime.
  func stop() {
    _ = ensureShutdownTask()
  }

  /// Stops the actor-owned runtime and waits for cleanup to finish.
  func stopAndWait() async {
    guard let shutdownTask = ensureShutdownTask() else { return }

    await shutdownTask.value
    self.shutdownTask = nil
  }

  /// Requests graceful shutdown, then calls the completion once cleanup is complete.
  func requestTermination(completion: @escaping @MainActor () -> Void) {
    guard terminationRequestTask == nil else { return }

    terminationRequestTask = Task { [weak self] in
      guard let self else { return }

      await self.completeTerminationRequest(completion: completion)
    }
  }

  /// Completes graceful shutdown before handing control back to AppKit termination.
  private func completeTerminationRequest(completion: @escaping @MainActor () -> Void) async {
    await stopAndWait()

    await MainActor.run {
      terminationRequestTask = nil
      completion()
    }
  }

  /// Applies all UI-side work required after a config reload.
  func handlePostConfigReloadUI() {
    installWidgetEditorStub()
    barWindowController?.reloadLayout()
    menuBarController?.setVisible(services.configSnapshotStore.snapshot.app.showMenuBarIcon)
    updateConfigIssueWindow()
  }

  /// Observes runtime config reload completion so UI stays in sync.
  private func installConfigReloadObserver() {
    guard configReloadObserver == nil else { return }

    configReloadObserver = NotificationCenter.default.addObserver(
      forName: .easyBarConfigReloadDidFinish,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.handlePostConfigReloadUI()
      }
    }
  }

  /// Keeps the config issue window in sync with load failures and active warnings.
  func updateConfigIssueWindow() {
    let reload: () -> Void = { [weak self] in
      guard let self else { return }

      Task {
        await self.runtimeCoordinator.reloadConfig()
      }
    }

    if let failureState = services.config.loadFailureState {
      configErrorWindowController.present(
        failureState: failureState,
        configPath: services.config.configPath,
        onReload: reload
      )
      return
    }

    let warnings = services.config.configWarnings
    guard !warnings.isEmpty else {
      configErrorWindowController.close()
      return
    }

    for warning in warnings {
      logger.warn(
        "config warning",
        .field("config_path", services.config.configPath),
        .field("warning", warning)
      )
    }

    configErrorWindowController.present(
      warnings: warnings,
      configPath: services.config.configPath,
      onReload: reload
    )
  }

  /// Configures file logging from the current app config.
  private func configureLogging() {
    AppShellSupport.configureLogging(
      logger: logger,
      minimumLevel: services.config.loggingLevel,
      fileLoggingEnabled: services.config.loggingEnabled,
      loggingDirectory: services.config.loggingDirectory,
      logFileName: "easybar.out"
    )
  }

  /// Creates and presents the main bar window controller.
  private func setupBarWindowController(menuFactory: EasyBarMenuFactory) {
    let controller = BarWindowController(
      logger: logger.child("window"),
      configStore: services.configSnapshotStore,
      widgetStore: services.widgetStore,
      aeroSpaceService: services.aeroSpaceService,
      appViewServices: AppViewServices(
        eventHub: services.eventHub,
        inboxStore: services.inboxStore,
        monthCalendarStore: services.nativeMonthCalendarStore,
        upcomingCalendarStore: services.nativeUpcomingCalendarStore,
        composerCalendarStore: services.nativeComposerCalendarStore,
        monthCalendarClient: services.monthCalendarAgentClient,
        upcomingCalendarClient: services.upcomingCalendarAgentClient,
        composerCalendarClient: services.composerCalendarAgentClient
      ),
      menuFactory: menuFactory
    )
    controller.present()
    barWindowController = controller
  }

  private func makeMenuStateProvider() -> BarContextMenuStateProvider {
    BarContextMenuStateProvider(
      nativeWiFiStore: services.nativeWiFiStore,
      nativeMonthCalendarStore: services.nativeMonthCalendarStore,
      nativeUpcomingCalendarStore: services.nativeUpcomingCalendarStore,
      monthCalendarAgentClient: services.monthCalendarAgentClient,
      upcomingCalendarAgentClient: services.upcomingCalendarAgentClient,
      networkAgentClient: services.networkAgentClient
    )
  }

  /// Creates the shared native menu factory.
  private func makeMenuFactory(stateProvider: BarContextMenuStateProvider) -> EasyBarMenuFactory {
    EasyBarMenuFactory(
      logger: logger.child("menu"),
      configStore: services.configSnapshotStore,
      actions: EasyBarMenuActions(
        start: { [weak self] in self?.startBar() },
        stop: { [weak self] in self?.stopBar() },
        restart: { [weak self] in self?.restartBar() },
        refresh: { [weak self] in self?.refreshRuntime() },
        reloadConfig: { [weak self] in self?.reloadConfig() },
        restartLuaRuntime: { [weak self] in self?.restartLuaRuntime() },
        restartCalendarAgent: { [weak self] in self?.restartCalendarAgent() },
        restartNetworkAgent: { [weak self] in self?.restartNetworkAgent() },
        selectTheme: { [weak self] name in self?.selectTheme(name) },
        setNativeWidgetEnabled: { [weak self] key, enabled in
          self?.setNativeWidgetEnabled(key, enabled: enabled)
        },
        setLogLevel: { [weak self] level in self?.setLogLevel(level) },
        quit: { [weak self] in self?.requestAppTermination() }
      ),
      stateProvider: stateProvider,
      runtimeState: { [weak self] in self?.barRuntimeState ?? .stopped }
    )
  }

  /// Creates the controller icon that survives bar-runtime shutdown.
  private func setupMenuBarController(menuFactory: EasyBarMenuFactory) {
    let controller = MenuBarController(menuFactory: menuFactory)
    controller.setVisible(services.configSnapshotStore.snapshot.app.showMenuBarIcon)
    menuBarController = controller
  }

  private func startBar() {
    runBarLifecycleTransition(finalState: .running) { [weak self] in
      guard let self else { return }
      await self.runtimeCoordinator.start()
      await MainActor.run { self.barWindowController?.present() }
    }
  }

  private func stopBar() {
    barWindowController?.hide()
    runBarLifecycleTransition(finalState: .stopped) { [weak self] in
      await self?.runtimeCoordinator.stop()
    }
  }

  private func restartBar() {
    barWindowController?.hide()
    runBarLifecycleTransition(finalState: .running) { [weak self] in
      guard let self else { return }
      await self.runtimeCoordinator.stop()
      await self.runtimeCoordinator.start()
      await MainActor.run { self.barWindowController?.present() }
    }
  }

  private func runBarLifecycleTransition(
    finalState: EasyBarRuntimeState,
    operation: @escaping @MainActor () async -> Void
  ) {
    guard barLifecycleTask == nil else { return }
    barRuntimeState = .transitioning
    barLifecycleTask = Task { [weak self] in
      await operation()
      guard let self else { return }

      if self.started {
        self.barRuntimeState = finalState
      }
      self.barLifecycleTask = nil
    }
  }

  private func refreshRuntime() {
    Task { await runtimeCoordinator.refreshRuntime() }
  }

  private func reloadConfig() {
    Task { await runtimeCoordinator.reloadConfig() }
  }

  private func restartLuaRuntime() {
    Task { await runtimeCoordinator.restartLuaRuntime() }
  }

  private func selectTheme(_ name: String?) {
    guard let name else {
      Task { await runtimeCoordinator.reloadConfig() }
      return
    }
    let persistence = ConfigPersistence(
      configPath: services.configSnapshotStore.snapshot.app.configPath,
      logger: logger.child("theme.config_persistence")
    )
    guard
      persistence.apply([
        TOMLEdit(path: ["theme", "name"], value: .string(name))
      ])
    else { return }
    Task { await runtimeCoordinator.reloadConfig() }
  }

  private func setNativeWidgetEnabled(_ key: String, enabled: Bool) {
    let persistence = ConfigPersistence(
      configPath: services.configSnapshotStore.snapshot.app.configPath,
      logger: logger.child("native_widgets.config_persistence")
    )
    guard
      persistence.apply([
        TOMLEdit(path: ["builtins", key, "enabled"], value: .bool(enabled))
      ])
    else { return }
    Task { await runtimeCoordinator.reloadConfig() }
  }

  private func setLogLevel(_ level: ProcessLogLevel) {
    let persistence = ConfigPersistence(
      configPath: services.configSnapshotStore.snapshot.app.configPath,
      logger: logger.child("logging.config_persistence")
    )
    guard
      persistence.apply([
        TOMLEdit(path: ["logging", "level"], value: .string(level.rawValue))
      ])
    else { return }

    let environmentOverride = ProcessLogLevel.normalized(
      ProcessInfo.processInfo.environment[SharedEnvironmentKeys.loggingLevel]
    )
    if let environmentOverride {
      logger.info(
        "persisted log level changed to \(level.rawValue)",
        .field("effective_level", environmentOverride.rawValue),
        .field("override", SharedEnvironmentKeys.loggingLevel)
      )
    } else {
      services.configSnapshotStore.applyLoggingLevelOverride(level)
      logger.setMinimumLevel(level)
      logger.info("runtime log level changed to \(level.rawValue)")
    }

    Task { await runtimeCoordinator.reloadConfig() }
  }

  private func restartCalendarAgent() {
    let socketPath = services.configSnapshotStore.snapshot.calendarAgent.socketPath
    restartAgent(name: "calendar") {
      try AgentRestartClient.restartCalendarAgent(socketPath: socketPath)
    }
  }

  private func restartNetworkAgent() {
    let socketPath = services.configSnapshotStore.snapshot.networkAgent.socketPath
    restartAgent(name: "network") {
      try AgentRestartClient.restartNetworkAgent(socketPath: socketPath)
    }
  }

  /// Runs one acknowledged helper-agent restart away from the main actor.
  private func restartAgent(
    name: String,
    operation: @escaping @Sendable () throws -> Void
  ) {
    Task.detached { [logger] in
      do {
        try operation()
        logger.info("\(name) agent restart acknowledged")
      } catch {
        logger.error("\(name) agent restart failed", .field("error", "\(error)"))
      }
    }
  }

  /// Installs the bundled Lua editor stub into the configured editor-stub path.
  private func installWidgetEditorStub() {
    widgetEditorStubInstaller.install(stubPath: services.config.widgetEditorStubPath)
  }

  /// Starts one shared shutdown task when the app is still running.
  private func ensureShutdownTask() -> Task<Void, Never>? {
    if let shutdownTask {
      return shutdownTask
    }

    guard started else { return nil }
    started = false
    barRuntimeState = .transitioning

    logger.info("easybar shutting down")
    signalHandler.stop()
    let pendingBarLifecycleTask = barLifecycleTask
    let shutdownTask = Task { [runtimeCoordinator] in
      await pendingBarLifecycleTask?.value
      await runtimeCoordinator.stop()
    }

    self.shutdownTask = shutdownTask
    return shutdownTask
  }
}
