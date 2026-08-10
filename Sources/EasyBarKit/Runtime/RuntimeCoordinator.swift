import EasyBarShared
import Foundation

/// Actor-owned runtime coordinator.
///
/// This remains the orchestration boundary for startup, shutdown, reloads,
/// runtime refreshes, and IPC commands. Lifecycle queue state, config watching,
/// and socket callback bridging are delegated to smaller runtime collaborators.
actor RuntimeCoordinator {
  private let logger: ProcessLogger
  private let services: AppServices
  private let configManager: ConfigManager
  private let fileWatcher: FileWatcher
  private let widgetEngine: WidgetEngine
  private let aeroSpaceService: AeroSpaceService
  private let socketServer: SocketServer
  private let rebindInstanceLock: @MainActor @Sendable (String) -> Bool

  private var lifecycle = RuntimeLifecycleStateMachine()
  private var configWatcherTask: Task<Void, Never>?

  init(
    logger: ProcessLogger,
    services: AppServices,
    rebindInstanceLock: @escaping @MainActor @Sendable (String) -> Bool
  ) {
    self.logger = logger
    self.services = services
    self.rebindInstanceLock = rebindInstanceLock
    self.configManager = services.configManager
    self.aeroSpaceService = services.aeroSpaceService
    self.fileWatcher = FileWatcher(logger: logger.child("file_watcher"))

    self.widgetEngine = WidgetEngine(
      logger: logger.child("widget_engine"),
      luaRuntime: services.luaRuntime,
      configManager: services.configManager,
      eventHub: services.eventHub,
      eventManager: services.eventManager,
      widgetStore: services.widgetStore,
      metricsCoordinator: services.metricsCoordinator,
      inboxStore: services.inboxStore
    )

    self.socketServer = SocketServer(
      logger: logger.child("socket_server"),
      metricsCoordinator: services.metricsCoordinator
    )
  }

  func start() async {
    guard let generation = lifecycle.start() else {
      logger.warn("runtime coordinator already started")
      return
    }

    logger.info("runtime coordinator start begin")

    let startupSnapshot = await configManager.snapshot()
    guard shouldContinueStartup(generation: generation) else { return }

    await configureLogging()
    guard shouldContinueStartup(generation: generation) else { return }

    await MainActor.run {
      services.applyRuntimeConfiguration(startupSnapshot)
      services.nativeWidgetRegistry.start(snapshot: startupSnapshot)
      aeroSpaceService.start()
    }
    guard shouldContinueStartup(generation: generation) else { return }

    await widgetEngine.start()
    guard shouldContinueStartup(generation: generation) else { return }

    await startConfigWatcher()
    guard shouldContinueStartup(generation: generation) else { return }

    await startSocketServer()

    aeroSpaceService.triggerRefresh()

    logger.info("runtime coordinator start end")
  }

  func stop() async {
    guard lifecycle.stop() else {
      logger.debug("runtime coordinator stop ignored because it is not started")
      return
    }

    logger.info("runtime coordinator stop begin")

    await stopConfigWatcher()
    await services.metricsCoordinator.setSnapshotHandler(nil)
    socketServer.stop()

    await widgetEngine.shutdown()

    await MainActor.run {
      services.nativeWidgetRegistry.stop()
      aeroSpaceService.stop()
    }

    logger.info("runtime coordinator stop end")
  }

  func reloadConfig() async {
    let operation = RuntimeLifecycleOperation.reloadConfig

    await withLifecycleOperation(
      operation,
      queuedMessage: "\(operation.rawValue) busy; queueing another reload"
    ) { generation in
      let result = await configManager.reload()
      guard shouldContinueLifecycleWork(generation: generation, operation: operation) else {
        return
      }

      guard
        await runConfigReloadSteps(
          result: result,
          generation: generation,
          operation: operation
        )
      else {
        return
      }

      aeroSpaceService.triggerRefresh()

      if let errorMessage = result.errorMessage {
        logger.warn(
          "config reload completed with error",
          .field("error", errorMessage),
        )
      }

      await MainActor.run {
        NotificationCenter.default.post(name: .easyBarConfigReloadDidFinish, object: nil)
      }

      logger.info("\(operation.rawValue) end")
    }
  }

  private func runConfigReloadSteps(
    result: ConfigManager.ReloadResult,
    generation: UInt64,
    operation: RuntimeLifecycleOperation
  ) async -> Bool {
    let socketPath = SharedPathDefaults.easyBarSocketPath(
      in: result.snapshot.app.runtimeDirectory
    )
    let previousSocketPath = SharedPathDefaults.easyBarSocketPath(
      in: result.previousSnapshot.app.runtimeDirectory
    )
    let socketOutcome = socketServer.reloadConfiguration(socketPath: socketPath)
    guard socketOutcome.succeeded else {
      await configManager.restorePreviousState()
      logger.error(
        "config reload rolled back after socket listener failure",
        .field("socket_path", "\(socketPath)")
      )
      return false
    }

    if result.snapshot.app.lockDirectory != result.previousSnapshot.app.lockDirectory {
      let acquired = await rebindInstanceLock(result.snapshot.app.lockDirectory)
      guard acquired else {
        let rollbackOutcome = socketServer.reloadConfiguration(
          socketPath: previousSocketPath
        )
        await configManager.restorePreviousState()
        logger.error(
          "config reload rolled back after instance lock failure",
          .field("lock_directory", result.snapshot.app.lockDirectory),
          .field("socket_rollback_succeeded", rollbackOutcome.succeeded)
        )
        return false
      }
    }

    guard await runLifecycleStep(generation: generation, operation: operation, configureLogging)
    else {
      return false
    }

    guard
      await runLifecycleStep(
        generation: generation, operation: operation,
        {
          await MainActor.run {
            services.applyRuntimeConfiguration(result.snapshot)
          }
        })
    else {
      return false
    }

    guard
      await runLifecycleStep(
        generation: generation,
        operation: operation,
        { await widgetEngine.reload() }
      )
    else {
      return false
    }

    guard
      await runLifecycleStep(
        generation: generation, operation: operation,
        {
          await MainActor.run {
            services.nativeWidgetRegistry.reload(snapshot: result.snapshot)
          }
        })
    else {
      return false
    }

    guard
      await runLifecycleStep(generation: generation, operation: operation, restartConfigWatcher)
    else {
      return false
    }

    let completed = shouldContinueLifecycleWork(generation: generation, operation: operation)
    if completed {
      await configManager.discardPreviousState()
    }
    return completed
  }

  func restartLuaRuntime() async {
    let operation = RuntimeLifecycleOperation.restartLuaRuntime

    await withLifecycleOperation(
      operation,
      queuedMessage: "\(operation.rawValue) busy; queueing another restart"
    ) { generation in
      await widgetEngine.reload()
      guard shouldContinueLifecycleWork(generation: generation, operation: operation) else {
        return
      }

      aeroSpaceService.triggerRefresh()

      logger.info("\(operation.rawValue) end")
    }
  }

  /// Refreshes the current runtime without reloading config.
  func refreshRuntime() async {
    logger.debug("refreshRuntime begin")
    aeroSpaceService.triggerRefresh()
    await services.eventHub.emit(.manualRefresh, source: "runtime manual_refresh")
    logger.debug("refreshRuntime end")
  }

  /// Validates config through the serialized config manager path.
  func validateConfig(configPathOverride: String?) async -> IPC.Message {
    logger.info(
      "validateConfig begin",
      .field("config_path_override", configPathOverride ?? "<default>")
    )

    let result = await configManager.validateConfig(configPathOverride: configPathOverride)

    if let errorMessage = result.errorMessage {
      logger.warn(
        "validateConfig failed",
        .field("config_path", result.configPath),
        .field("error", errorMessage)
      )
      return .rejected(message: errorMessage)
    }

    for warning in result.warnings {
      logger.warn(
        "validateConfig warning",
        .field("config_path", result.configPath),
        .field("warning", warning)
      )
    }

    logger.info(
      "validateConfig succeeded",
      .field("config_path", result.configPath),
      .field("warnings", "\(result.warnings.count)")
    )
    return .configValidated(configPath: result.configPath, warnings: result.warnings)
  }

  /// Handles one incoming IPC command.
  func handleSocketCommand(_ command: IPC.Command) async {
    logger.debug(
      "handling socket command",
      .field("command", command),
    )

    switch command {
    case .manualRefresh:
      await refreshRuntime()

    case .workspaceChange:
      aeroSpaceService.triggerRefresh()
      await services.eventHub.emit(.workspaceChange, source: "script \(command.rawValue)")

    case .focusChange:
      aeroSpaceService.triggerRefresh()
      await services.eventHub.emit(.focusChange, source: "script \(command.rawValue)")

    case .spaceModeChange:
      aeroSpaceService.triggerRefresh()
      await services.eventHub.emit(.spaceModeChange, source: "script \(command.rawValue)")

    case .reloadConfig:
      await reloadConfig()

    case .restartLuaRuntime:
      await restartLuaRuntime()

    case .validateConfig:
      break

    case .metrics, .logs:
      break

    case .inboxSend, .inboxRead, .inboxMarkRead, .inboxMarkUnread, .inboxDismiss, .inboxRemove,
      .inboxClear:
      break
    }
  }

  /// Handles one typed inbox query or mutation on the main-actor store.
  private func handleInboxRequest(_ request: IPC.InboxRequest) async -> IPC.Message {
    await MainActor.run {
      switch request.operation {
      case .send:
        guard let payload = request.item else {
          return .rejected(message: "inbox send requires an item")
        }
        if let value = payload.url {
          guard let url = URL(string: value), url.host != nil,
            let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https"
          else {
            return .rejected(message: "inbox URL must use http or https")
          }
        }
        let item = InboxItem(
          id: payload.id,
          title: payload.title,
          body: payload.message,
          timestamp: payload.timestamp,
          category: payload.group,
          severity: InboxSeverity(rawValue: payload.severity.rawValue),
          unread: payload.unread,
          source: InboxSourcePresentation(name: payload.source, icon: nil, color: nil),
          url: payload.url
        )
        guard services.inboxStore.upsert(source: payload.source, item: item) else {
          return .rejected(message: "invalid inbox item")
        }
        return .accepted

      case .read:
        return .inbox(
          services.inboxStore.ipcItems(source: request.source, unreadOnly: request.unreadOnly)
        )

      case .markRead, .markUnread:
        let changed = services.inboxStore.setRead(
          request.operation == .markRead,
          source: request.source,
          id: request.id
        )
        return changed ? .accepted : .rejected(message: "no matching inbox items")

      case .dismiss:
        let changed = services.inboxStore.dismiss(source: request.source, id: request.id)
        return changed ? .accepted : .rejected(message: "no matching dismissible inbox items")

      case .remove:
        guard let source = request.source, let id = request.id else {
          return .rejected(message: "inbox remove requires source and id")
        }
        return services.inboxStore.remove(source: source, id: id)
          ? .accepted : .rejected(message: "no matching inbox item")

      case .clear:
        if let source = request.source {
          services.inboxStore.clearFromControl(source: source)
        } else {
          services.inboxStore.clearAll()
        }
        return .accepted
      }
    }
  }

  /// Configures runtime logging from the current config.
  private func configureLogging() async {
    let minimumLevel = await configManager.loggingLevel()
    let fileLoggingEnabled = await configManager.loggingEnabled()
    let loggingDirectory = await configManager.loggingDirectory()

    logger.configureRuntimeLogging(
      minimumLevel: minimumLevel,
      fileLoggingEnabled: fileLoggingEnabled,
      fileLoggingPath: easyBarLogPath(in: loggingDirectory)
    )
  }

  /// Starts the config watcher loop.
  private func startConfigWatcher() async {
    configWatcherTask?.cancel()

    let path = await configManager.configPath()
    let enabled = await configManager.watchConfigFileEnabled()
    let stream = await fileWatcher.start(configPath: path, enabled: enabled)

    configWatcherTask = Task { [weak self] in
      for await event in stream {
        guard case .changed = event else { continue }
        await self?.reloadConfig()
      }
    }
  }

  /// Restarts the config watcher after a config reload.
  private func restartConfigWatcher() async {
    await stopConfigWatcher()
    await startConfigWatcher()
  }

  /// Stops consuming config changes and closes the filesystem watcher.
  private func stopConfigWatcher() async {
    configWatcherTask?.cancel()
    configWatcherTask = nil
    await fileWatcher.stop()
  }

  /// Returns whether one in-flight lifecycle operation is still allowed to mutate runtime state.
  private func shouldContinueLifecycleWork(
    generation: UInt64,
    operation: RuntimeLifecycleOperation
  ) -> Bool {
    let currentGeneration = lifecycle.generation

    guard lifecycle.canContinueLifecycleWork(generation: generation) else {
      logger.debug(
        "\(operation.rawValue) aborted because runtime stopped or restarted",
        .field("generation", "\(generation)"),
        .field("current_generation", "\(currentGeneration)"),
      )
      return false
    }

    return true
  }

  /// Runs one lifecycle step and returns whether subsequent work may continue.
  private func runLifecycleStep(
    generation: UInt64,
    operation: RuntimeLifecycleOperation,
    _ work: () async -> Void
  ) async -> Bool {
    await work()
    return shouldContinueLifecycleWork(generation: generation, operation: operation)
  }

  /// Runs one serialized lifecycle operation and always releases lifecycle ownership.
  private func withLifecycleOperation(
    _ operation: RuntimeLifecycleOperation,
    queuedMessage: String,
    _ work: (UInt64) async -> Void
  ) async {
    let generation: UInt64

    switch lifecycle.begin(operation) {
    case .notStarted:
      logger.debug("\(operation.rawValue) ignored because runtime is stopped")
      return
    case .queued:
      logger.debug(queuedMessage)
      return
    case .started(let startedGeneration):
      generation = startedGeneration
    }

    logger.info("\(operation.rawValue) begin")

    await work(generation)
    await finishLifecycleOperation(operation)
  }

  /// Marks one lifecycle operation finished and runs the next queued operation when present.
  private func finishLifecycleOperation(_ operation: RuntimeLifecycleOperation) async {
    switch lifecycle.finish() {
    case .reloadConfig:
      await reloadConfig()
    case .restartLuaRuntime:
      await restartLuaRuntime()
    case nil:
      break
    }
  }

  /// Returns whether startup work can still continue for the provided generation.
  private func shouldContinueStartup(generation: UInt64) -> Bool {
    guard lifecycle.canContinueStartup(generation: generation) else {
      logger.debug(
        "startup aborted because runtime stopped or restarted",
        .field("generation", "\(generation)"),
        .field("current_generation", "\(lifecycle.generation)"),
      )
      return false
    }

    return true
  }

  /// Starts the IPC socket server.
  private func startSocketServer() async {
    let socketPath = await configManager.easyBarSocketPath()
    socketServer.reloadConfiguration(socketPath: socketPath)

    await services.metricsCoordinator.setSnapshotHandler { [weak self] snapshot in
      Task {
        await self?.broadcastMetrics(snapshot)
      }
    }

    socketServer.start { [weak self] command in
      Task {
        await self?.handleSocketCommand(command)
      }
    } validateConfigHandler: { [weak self] configPathOverride in
      guard let self else {
        return .rejected(message: "config validation unavailable")
      }

      return await self.validateConfig(configPathOverride: configPathOverride)
    } inboxHandler: { [weak self] request in
      guard let self else {
        return .rejected(message: "inbox control unavailable")
      }
      return await self.handleInboxRequest(request)
    }
  }

  /// Broadcasts one metrics snapshot through the runtime socket server.
  private func broadcastMetrics(_ snapshot: IPC.MetricsSnapshot) {
    socketServer.broadcastMetrics(snapshot)
  }
}

extension Notification.Name {
  /// Posted after one config reload attempt finishes and UI should resync.
  static let easyBarConfigReloadDidFinish = Notification.Name("easybar.configReloadDidFinish")
}

/// Returns the EasyBar log path inside one logging directory.
private func easyBarLogPath(in directory: String) -> String {
  URL(fileURLWithPath: directory)
    .appendingPathComponent("easybar.out")
    .path
}
