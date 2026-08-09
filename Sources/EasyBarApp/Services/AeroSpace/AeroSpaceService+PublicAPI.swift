import AppKit
import EasyBarShared
import Foundation

// MARK: - Public API

extension AeroSpaceService {
  /// Returns whether any native widget currently needs AeroSpace state.
  var hasConsumers: Bool {
    withLock { !$0.consumers.isEmpty }
  }

  /// Returns whether AeroSpace observation is currently active.
  var isActive: Bool {
    withLock { $0.acceptsWork }
  }

  /// Returns the current registered consumer count.
  var consumerCount: Int {
    withLock { $0.consumers.count }
  }

  /// Starts the service lifecycle. Expensive observation starts when consumers register.
  func start() {
    let shouldStart = withLock { coordination -> Bool in
      guard !coordination.running else { return false }
      coordination.running = true
      coordination.generation &+= 1
      return true
    }

    guard shouldStart else { return }

    logger.debug("aerospace service start begin")
    if hasConsumers {
      _ = activateIfNeeded(source: "service started")
    }
    logger.debug("aerospace service start end")
  }

  /// Stops the service and prevents queued refresh work from publishing.
  func stop() {
    guard withLock({ $0.running }) else { return }

    deactivateIfNeeded(reason: "service stopped")

    withLock { coordination in
      coordination.running = false
      coordination.consumers.removeAll()
      coordination.generation &+= 1
    }

    logger.debug("aerospace service stop end")
  }

  /// Registers one widget that depends on AeroSpace state.
  func registerConsumer(
    _ id: String,
    onUpdate: @escaping @MainActor @Sendable () -> Void
  ) {
    let count = withLock { coordination -> Int in
      coordination.consumers[id] = onUpdate
      return coordination.consumers.count
    }

    logger.debug(
      "aerospace consumer registered",
      .field("id", id),
      .field("count", count)
    )

    if !activateIfNeeded(source: "consumer registered") {
      refresh()
    }
  }

  /// Unregisters one widget that no longer depends on AeroSpace state.
  func unregisterConsumer(_ id: String) {
    let count = withLock { coordination -> Int in
      coordination.consumers.removeValue(forKey: id)
      return coordination.consumers.count
    }

    logger.debug(
      "aerospace consumer unregistered",
      .field("id", id),
      .field("count", count)
    )

    if count == 0 {
      deactivateIfNeeded(reason: "last consumer unregistered")
    }
  }

  /// Called by the socket server when an external AeroSpace event occurs.
  func triggerRefresh() {
    triggerRefresh(source: "external trigger")
  }

  /// Queues a state reload for one AeroSpace-triggered update source.
  func triggerRefresh(source: String) {
    guard isActive else {
      logger.debug("aerospace refresh skipped, service inactive or no registered consumers")
      return
    }

    queueRefresh(source: source)
  }

  /// Focuses the requested workspace and rolls back the optimistic state on command failure.
  @MainActor
  func focusWorkspace(_ workspace: String) {
    logger.info(
      "aerospace focus workspace requested",
      .field("workspace", workspace)
    )

    guard spaces.contains(where: { $0.name == workspace }) else {
      logger.warn(
        "cannot focus unknown AeroSpace workspace",
        .field("workspace", workspace)
      )
      return
    }

    let previousSpaces = spaces
    replaceSpaces(
      spaces.map { space in
        SpaceItem(
          id: space.id,
          name: space.name,
          isFocused: space.name == workspace,
          isVisible: space.isVisible,
          apps: space.apps
        )
      })
    notifyConsumers()

    let reservation = reserveWorkspaceFocus()
    guard let reservation else {
      replaceSpaces(previousSpaces)
      notifyConsumers()
      return
    }
    reservation.replacedTask?.cancel()

    let task = Task.detached(priority: .userInitiated) { [weak self] in
      guard let self else { return }
      defer { self.finishWorkspaceFocus(reservation.token) }
      guard self.shouldExecute(workspaceFocusToken: reservation.token) else { return }

      guard await self.runAeroSpace(arguments: ["workspace", workspace]) != nil else {
        guard self.shouldExecute(workspaceFocusToken: reservation.token) else { return }
        await self.rollbackWorkspaceFocus(
          previousSpaces,
          workspace: workspace,
          token: reservation.token
        )
        return
      }

      guard self.shouldExecute(workspaceFocusToken: reservation.token) else { return }
      self.logger.debug(
        "aerospace workspace focused",
        .field("workspace", workspace)
      )
      self.queueRefresh(
        source: "workspace focus completed",
        expectedGeneration: reservation.token.generation
      )
    }

    let shouldCancel = withLock { state -> Bool in
      guard state.pendingWorkspaceFocusToken == reservation.token else { return true }
      state.workspaceFocusTask = task
      return false
    }
    if shouldCancel {
      task.cancel()
    }
  }

  /// Activates one application shown inside a workspace.
  @MainActor
  func focusApp(_ app: SpaceApp) {
    logger.info(
      "aerospace focus app requested",
      .field("app", app.name)
    )

    guard let bundlePath = app.bundlePath, !bundlePath.isEmpty else {
      logger.debug(
        "aerospace focus app skipped, missing bundle path",
        .field("app", app.name)
      )
      return
    }

    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true

    NSWorkspace.shared.openApplication(
      at: URL(fileURLWithPath: bundlePath),
      configuration: configuration
    ) { [logger] _, error in
      if let error {
        logger.debug(
          "failed to focus app",
          .field("app", app.name),
          .field("error", error)
        )
      }
    }
  }

  /// Returns whether the focused application can currently be hidden.
  @MainActor
  var canHideFocusedApp: Bool {
    guard let app = focusedApp else { return false }
    return runningApplication(for: app) != nil
  }

  /// Returns whether the focused application bundle can be revealed in Finder.
  @MainActor
  var canRevealFocusedApp: Bool {
    guard let path = focusedApp?.bundlePath, !path.isEmpty else { return false }
    return FileManager.default.fileExists(atPath: path)
  }

  /// Hides the application represented by the current AeroSpace snapshot.
  @MainActor
  @discardableResult
  func hideFocusedApp() -> Bool {
    guard let app = focusedApp else {
      logger.warn("cannot hide focused app, AeroSpace has no focused application")
      return false
    }
    guard let runningApplication = runningApplication(for: app) else {
      logger.warn(
        "cannot hide focused app, running application was not resolved",
        .field("app", app.name)
      )
      return false
    }
    guard runningApplication.hide() else {
      logger.warn("failed to hide focused app", .field("app", app.name))
      return false
    }
    logger.debug("hid focused app", .field("app", app.name))
    return true
  }

  /// Reveals the focused application bundle in Finder.
  @MainActor
  @discardableResult
  func revealFocusedAppInFinder() -> Bool {
    guard let app = focusedApp else {
      logger.warn("cannot reveal focused app, AeroSpace has no focused application")
      return false
    }
    guard let path = app.bundlePath, !path.isEmpty else {
      logger.warn("cannot reveal focused app, bundle path is missing", .field("app", app.name))
      return false
    }
    guard FileManager.default.fileExists(atPath: path) else {
      logger.warn(
        "cannot reveal focused app, bundle path does not exist",
        .field("app", app.name),
        .field("path", path)
      )
      return false
    }

    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    logger.debug("revealed focused app in Finder", .field("app", app.name))
    return true
  }

  /// Resolves the running application represented by one AeroSpace app snapshot.
  @MainActor
  private func runningApplication(for app: SpaceApp) -> NSRunningApplication? {
    if !app.bundleID.isEmpty,
      let running = NSWorkspace.shared.runningApplications.first(where: { running in
        running.bundleIdentifier == app.bundleID
      })
    {
      return running
    }

    guard let path = app.bundlePath, !path.isEmpty else { return nil }
    return NSWorkspace.shared.runningApplications.first { running in
      running.bundleURL?.path == path
    }
  }

  /// Changes the focused AeroSpace window/container layout and reloads state.
  func setFocusedLayout(_ mode: AeroSpaceLayoutMode) {
    guard mode != .unknown else {
      logger.warn("ignored unsupported AeroSpace layout request")
      return
    }

    logger.info(
      "aerospace layout requested",
      .field("layout", mode.rawValue)
    )

    let generation = currentGeneration()

    Task.detached(priority: .userInitiated) { [weak self] in
      guard let self else { return }
      guard self.shouldExecute(generation: generation) else { return }
      guard await self.runAeroSpace(arguments: AeroSpaceCommandArguments.layout(mode)) != nil else {
        self.logger.warn(
          "failed to change AeroSpace layout",
          .field("layout", mode.rawValue)
        )
        return
      }
      self.logger.debug(
        "changed AeroSpace layout",
        .field("layout", mode.rawValue)
      )
      guard self.shouldExecute(generation: generation) else { return }
      self.queueRefresh(source: "layout change completed", expectedGeneration: generation)
    }
  }

  /// Opens the configuration file currently loaded by AeroSpace.
  func openConfig() {
    let generation = currentGeneration()

    Task.detached(priority: .userInitiated) { [weak self] in
      guard let self else { return }
      guard self.shouldExecute(generation: generation) else { return }
      guard
        let path = await self.runAeroSpace(arguments: AeroSpaceCommandArguments.configPath),
        !path.isEmpty
      else {
        self.logger.warn("failed to resolve AeroSpace config path")
        return
      }
      guard FileManager.default.fileExists(atPath: path) else {
        self.logger.warn(
          "AeroSpace config path does not exist",
          .field("path", path)
        )
        return
      }

      Task { @MainActor in
        guard NSWorkspace.shared.open(URL(fileURLWithPath: path)) else {
          self.logger.warn(
            "failed to open AeroSpace config",
            .field("path", path)
          )
          return
        }
        self.logger.debug("opened AeroSpace config", .field("path", path))
      }
    }
  }

  /// Public refresh entry.
  func refresh() {
    guard isActive else {
      logger.debug("aerospace refresh skipped, service inactive or no registered consumers")
      return
    }

    queueRefresh(source: "explicit refresh")
  }
}
