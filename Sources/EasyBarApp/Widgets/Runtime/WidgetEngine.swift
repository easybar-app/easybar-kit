import EasyBarShared
import Foundation

private struct WidgetRuntimeState {
  var requiredEvents = Set<String>()
  var isReady = false
  var hasSubscriptions = false
  var didEmitInitialEvents = false

  var canEmitInitialEvents: Bool {
    isReady && hasSubscriptions && !didEmitInitialEvents
  }

  mutating func reset() {
    self = WidgetRuntimeState()
  }
}

/// Actor-owned scripted widget runtime.
///
/// This actor owns the Lua handshake state, subscriptions, and tree updates.
actor WidgetEngine {
  /// Maximum complete protocol lines waiting for actor-side processing.
  static let maximumBufferedRuntimeLines = 256

  private let logger: ProcessLogger
  private let configManager: ConfigManager
  private let luaRuntime: LuaRuntime
  private let eventHub: EventHub
  private let eventManager: EventManager
  private let widgetStore: WidgetStore
  private let metricsCoordinator: MetricsCoordinator
  private let inboxStore: InboxStore
  private let commandService: LuaCommandService
  private let timerService: LuaTimerService
  private let storageService: LuaStorageService
  private let protocolDecoder = WidgetRuntimeProtocolDecoder()

  private var runtimeState = WidgetRuntimeState()
  private var scriptedRoots = Set<String>()
  private var started = false
  private var runtimeAvailable = false
  private var runtimeSessionID: UInt64 = 0
  private var runtimeLineBuffer: LuaRuntimeLineBuffer?
  private var runtimeLineTask: Task<Void, Never>?
  private var runtimeInputOverflowSessionID: UInt64?
  private let restartScheduler: BackoffScheduler

  init(
    logger: ProcessLogger,
    luaRuntime: LuaRuntime,
    configManager: ConfigManager,
    eventHub: EventHub,
    eventManager: EventManager,
    widgetStore: WidgetStore,
    metricsCoordinator: MetricsCoordinator,
    inboxStore: InboxStore
  ) {
    self.logger = logger
    self.configManager = configManager
    self.luaRuntime = luaRuntime
    self.eventHub = eventHub
    self.eventManager = eventManager
    self.widgetStore = widgetStore
    self.metricsCoordinator = metricsCoordinator
    self.inboxStore = inboxStore
    self.commandService = LuaCommandService(
      logger: logger.child("commands"),
      luaRuntime: luaRuntime,
      configManager: configManager
    )
    self.timerService = LuaTimerService(
      logger: logger.child("timers"),
      luaRuntime: luaRuntime
    )
    self.storageService = LuaStorageService(
      logger: logger.child("storage"),
      luaRuntime: luaRuntime,
      configManager: configManager
    )
    self.restartScheduler = BackoffScheduler(
      label: "lua runtime restart",
      delays: [1, 2, 5, 10, 30],
      logger: logger,
      logLevel: .warn
    )
  }

  @discardableResult
  func start() async -> Bool {
    guard !started else {
      logger.debug("widget engine already started")
      return true
    }

    logger.debug("widget engine start begin")
    started = true

    guard await startRuntimeSession() else {
      started = false
      logger.warn("widget engine start failed because lua runtime did not launch")
      return false
    }

    logger.debug("widget engine start end")
    return true
  }

  /// Starts one fresh Lua child-process session for the active widget engine.
  private func startRuntimeSession() async -> Bool {
    runtimeState.reset()
    await commandService.resetActiveAsyncCommandCount()
    await timerService.reset()
    await eventHub.resetLuaEventSink()

    runtimeSessionID &+= 1
    let sessionID = runtimeSessionID
    runtimeAvailable = false
    runtimeInputOverflowSessionID = nil

    let lineBuffer = LuaRuntimeLineBuffer(
      maximumBufferedLines: Self.maximumBufferedRuntimeLines
    )
    runtimeLineBuffer = lineBuffer
    runtimeLineTask = Task { [weak self] in
      for await line in lineBuffer.stream {
        guard let self else { return }
        await self.handleRuntimeTransportLine(line, runtimeSessionID: sessionID)
      }
    }

    await luaRuntime.setLineHandler { [weak self] line in
      guard lineBuffer.enqueue(line) == .overflow else { return }
      Task {
        await self?.handleRuntimeInputOverflow(runtimeSessionID: sessionID)
      }
    }
    await luaRuntime.setTerminationHandler { [weak self] termination in
      Task {
        await self?.handleRuntimeTermination(
          termination,
          runtimeSessionID: sessionID
        )
      }
    }

    let configSnapshot = await configManager.snapshot()

    guard await luaRuntime.start(config: configSnapshot) else {
      invalidateRuntimeSession()
      await luaRuntime.setLineHandler { _ in }
      await luaRuntime.setTerminationHandler { _ in }
      return false
    }

    guard acceptsRuntimeSession(sessionID, whileRunning: started) else {
      await luaRuntime.shutdown()
      return false
    }

    runtimeAvailable = true
    return true
  }

  func reload() async {
    logger.debug("widget engine reload begin")

    let rootsToClear = scriptedRoots
    await shutdown()

    await MainActor.run {
      widgetStore.clear(owners: Set(rootsToClear.map { .scripted(root: $0) }))
      inboxStore.clearPublishedItems()
    }

    scriptedRoots.removeAll()
    let didRestart = await start()
    if !didRestart {
      logger.warn("widget engine reload completed without restarting lua runtime")
    }

    logger.debug("widget engine reload end")
  }

  func shutdown() async {
    guard started || runtimeAvailable else {
      restartScheduler.cancel()
      logger.debug("widget engine shutdown skipped, not started")
      return
    }

    logger.debug("widget engine shutdown begin")

    started = false
    runtimeAvailable = false
    restartScheduler.cancel()
    invalidateRuntimeSession()
    runtimeState.reset()
    await commandService.resetActiveAsyncCommandCount()
    await timerService.reset()

    await eventHub.clearLuaForwardedAppEvents()

    await MainActor.run {
      eventManager.stopLuaSubscriptions()
      inboxStore.clearPublishedItems()
    }

    await luaRuntime.setLineHandler { _ in }
    await luaRuntime.setTerminationHandler { _ in }
    await luaRuntime.shutdown()

    logger.debug("widget engine shutdown end")
  }

  /// Handles an observed Lua child-process exit for one runtime session.
  private func handleRuntimeTermination(
    _ termination: LuaProcessController.Termination,
    runtimeSessionID: UInt64
  ) async {
    guard acceptsRuntimeSession(runtimeSessionID, whileRunning: started) else { return }

    runtimeAvailable = false
    invalidateRuntimeSession()
    runtimeState.reset()
    await commandService.resetActiveAsyncCommandCount()
    await timerService.reset()
    await eventHub.clearLuaForwardedAppEvents()

    let rootsToClear = scriptedRoots
    scriptedRoots.removeAll()

    await MainActor.run {
      eventManager.stopLuaSubscriptions()
      widgetStore.clear(owners: Set(rootsToClear.map { .scripted(root: $0) }))
      inboxStore.clearPublishedItems()
    }

    guard !termination.wasRequested else { return }

    logger.warn(
      "lua runtime exited unexpectedly",
      .field("pid", termination.processIdentifier),
      .field("reason", String(describing: termination.reason))
    )

    scheduleRuntimeRestart(expectedSessionID: self.runtimeSessionID)
  }

  /// Schedules one bounded-backoff restart while the widget engine still wants to run.
  private func scheduleRuntimeRestart(expectedSessionID: UInt64) {
    restartScheduler.schedule { [weak self] in
      Task {
        await self?.restartRuntimeAfterUnexpectedExit(
          expectedSessionID: expectedSessionID
        )
      }
    }
  }

  /// Attempts one recovery launch and reschedules when startup still fails.
  private func restartRuntimeAfterUnexpectedExit(expectedSessionID: UInt64) async {
    guard started, !runtimeAvailable, runtimeSessionID == expectedSessionID else { return }

    if await startRuntimeSession() {
      logger.info("lua runtime restarted after unexpected exit")
      return
    }

    guard started else { return }
    scheduleRuntimeRestart(expectedSessionID: runtimeSessionID)
  }

  /// Restarts a runtime that can no longer keep up with valid protocol input.
  private func handleRuntimeInputOverflow(runtimeSessionID: UInt64) async {
    guard acceptsRuntimeSession(runtimeSessionID, whileRunning: started && runtimeAvailable),
      runtimeInputOverflowSessionID != runtimeSessionID
    else {
      return
    }

    runtimeInputOverflowSessionID = runtimeSessionID
    await metricsCoordinator.recordLuaRuntimeInputOverflow()
    logger.error(
      "lua runtime input buffer overflowed; restarting runtime",
      .field("runtime_session_id", runtimeSessionID),
      .field("maximum_buffered_lines", Self.maximumBufferedRuntimeLines)
    )
    await luaRuntime.terminateForRecovery(reason: "runtime input buffer overflow")
  }

  func handleRuntimeTransportLine(_ line: String, runtimeSessionID: UInt64) async {
    guard
      acceptsRuntimeSession(
        runtimeSessionID,
        whileRunning: started && runtimeAvailable
      )
    else {
      logger.debug(
        "dropping stale lua transport line",
        .field("runtime_session_id", runtimeSessionID)
      )
      return
    }

    do {
      let message = try protocolDecoder.decodeMessage(from: line)
      await handleRuntimeMessage(message)
    } catch WidgetRuntimeProtocolError.unsupportedProtocolVersion(let version) {
      await metricsCoordinator.recordDecodeError()
      logger.warn(
        "unsupported lua protocol version",
        .field("expected", easyBarLuaRuntimeProtocolVersion),
        .field("received", version.map(String.init(describing:)) ?? "nil")
      )
    } catch DecodingError.dataCorrupted {
      await metricsCoordinator.recordDecodeError()
      logger.warn("invalid lua transport utf8", .field("bytes", line.utf8.count))
    } catch WidgetRuntimeProtocolError.invalidPayload(let message) {
      logger.warn(message)
    } catch {
      await metricsCoordinator.recordDecodeError()
      logger.warn("lua transport json decode failed", .field("bytes", line.utf8.count))
      logger.debug("decode error: \(error)")
    }
  }

  private func emitInitialEventsIfPossible() async {
    guard runtimeState.canEmitInitialEvents else { return }

    runtimeState.didEmitInitialEvents = true
    logger.debug("emitting replayable widget events")

    await eventHub.emitReplayableState(for: runtimeState.requiredEvents)
    await eventHub.emit(.manualRefresh)
  }

  private func handleRuntimeMessage(_ message: WidgetRuntimeMessage) async {
    switch message {
    case .subscriptions(let requiredEvents):
      await handleSubscriptions(requiredEvents)
    case .ready:
      await handleReady()
    case .tree(let root, let nodes):
      await handleTree(root: root, nodes: nodes)
    case .clearRoot(let rootID):
      await handleClearRoot(rootID: rootID)
    case .commandRequest(
      let token,
      let invocation,
      let isSynchronous,
      let timeoutSeconds,
      let maxOutputBytes,
      let widget,
      let operation):
      await commandService.handleCommandRequest(
        token: token,
        invocation: invocation,
        isSynchronous: isSynchronous,
        timeoutSecondsOverride: timeoutSeconds,
        maxOutputBytesOverride: maxOutputBytes,
        widget: widget,
        operation: operation,
        runtimeSessionID: runtimeSessionID,
        isRuntimeSessionActive: { [weak self] sessionID in
          guard let self else { return false }
          return await self.isRuntimeSessionActive(sessionID)
        }
      )
    case .commandCancel(let token):
      await commandService.cancelAsyncCommand(
        token: token,
        runtimeSessionID: runtimeSessionID
      )
    case .timerRequest(let token, let delaySeconds):
      await timerService.schedule(
        token: token,
        delaySeconds: delaySeconds,
        runtimeSessionID: runtimeSessionID,
        isRuntimeSessionActive: { [weak self] sessionID in
          guard let self else { return false }
          return await self.isRuntimeSessionActive(sessionID)
        }
      )
    case .timerCancel(let token):
      await timerService.cancel(token: token, runtimeSessionID: runtimeSessionID)
    case .inboxReplace(let snapshot):
      await MainActor.run {
        inboxStore.replace(source: snapshot.source, items: snapshot.items)
      }
    case .inboxClear(let source):
      await MainActor.run {
        inboxStore.clear(source: source)
      }
    case .inboxConfigure(let configuration):
      await MainActor.run {
        inboxStore.configure(source: configuration.source, actions: configuration.actions)
      }
    case .storageRequest(let token, let widget, let key, let operation, let value):
      await storageService.handle(
        token: token,
        widget: widget,
        key: key,
        operation: operation,
        value: value
      )
    }
  }

  private func isRuntimeSessionActive(_ sessionID: UInt64) -> Bool {
    acceptsRuntimeSession(sessionID, whileRunning: started && runtimeAvailable)
  }

  /// Invalidates queued work captured by the active Lua process generation.
  private func invalidateRuntimeSession() {
    runtimeSessionID &+= 1
    runtimeLineBuffer?.finish()
    runtimeLineBuffer = nil
    runtimeLineTask?.cancel()
    runtimeLineTask = nil
  }

  /// Returns whether work belongs to the active Lua process generation.
  private func acceptsRuntimeSession(_ candidate: UInt64, whileRunning: Bool) -> Bool {
    whileRunning && runtimeSessionID == candidate
  }

  private func handleSubscriptions(_ requiredEvents: Set<String>) async {
    runtimeState.requiredEvents = requiredEvents
    runtimeState.hasSubscriptions = true

    await metricsCoordinator.recordLuaSubscriptions(runtimeState.requiredEvents)
    logger.debug("required events updated", .field("events", runtimeState.requiredEvents))

    let requiredEvents = runtimeState.requiredEvents
    await eventHub.setLuaForwardedAppEvents(requiredEvents)

    await MainActor.run {
      eventManager.setLuaSubscriptions(requiredEvents)
    }

    await emitInitialEventsIfPossible()
  }

  private func handleReady() async {
    logger.debug("lua runtime handshake received")

    restartScheduler.resetDelay()
    runtimeState.isReady = true
    await metricsCoordinator.recordLuaReady()

    await emitInitialEventsIfPossible()
  }

  /// Handles one rendered widget tree update.
  private func handleTree(root: String, nodes: [WidgetNodeState]) async {
    scriptedRoots.insert(root)

    logger.debug(
      "decoded widget tree",
      .field("root", root),
      .field("nodes", nodes.count)
    )
    await metricsCoordinator.recordTreeUpdate(root: root, nodeCount: nodes.count)

    let applyResult = await MainActor.run {
      widgetStore.apply(owner: .scripted(root: root), nodes: nodes)
    }

    if !applyResult.rejectedNodeIDs.isEmpty {
      logger.warn(
        "rejected invalid widget tree nodes",
        .field("root", root),
        .field("duplicate_ids", applyResult.duplicateNodeIDs.sorted()),
        .field("mismatched_root_ids", applyResult.mismatchedRootNodeIDs.sorted()),
        .field("conflicting_ids", applyResult.conflictingNodeIDs.sorted())
      )
    }
  }

  /// Handles one explicit root-clear update from Lua.
  private func handleClearRoot(rootID: String) async {
    guard scriptedRoots.remove(rootID) != nil else {
      logger.warn("ignored clear for unknown scripted widget root", .field("root", rootID))
      return
    }
    logger.debug("decoded widget root clear", .field("root", rootID))

    await MainActor.run {
      widgetStore.clear(owners: [.scripted(root: rootID)])
    }
  }
}
