import EasyBarShared
import Foundation

extension LuaProcessController {
  /// Resolves the launch inputs for one Lua runtime process.
  func launchContext(config: ConfigSnapshot) -> LaunchContext? {
    guard let runtimePath = resolvedRuntimePath() else { return nil }
    guard let runtimeAgentPath = resolvedRuntimeAgentPath() else { return nil }

    do {
      try FileManager.default.createDirectory(
        atPath: config.logging.directory,
        withIntermediateDirectories: true
      )
    } catch {
      logger.warn(
        "failed to create lua widget logging directory",
        .field("path", config.logging.directory),
        .field("error", "\(error)")
      )
    }

    return LaunchContext(
      runtimeAgentPath: runtimeAgentPath,
      runtimePath: runtimePath,
      luaPath: config.app.luaPath,
      luaSocketPath: config.app.luaSocketPath,
      transportAuthenticationToken: UUID().uuidString.replacingOccurrences(of: "-", with: ""),
      widgetsPath: config.app.widgetsPath,
      defaultCommandTimeoutSeconds: config.app.luaCommandLimits.timeoutSeconds,
      defaultCommandMaxOutputBytes: config.app.luaCommandLimits.maxOutputBytes,
      environment: luaRuntimeEnvironment(config: config)
    )
  }

  /// Resolves the bundled Lua runtime script path.
  func resolvedRuntimePath() -> String? {
    guard let runtime = AppResourceLocator.url(forResource: "runtime", withExtension: "lua") else {
      logger.error("runtime.lua not found")
      return nil
    }
    return runtime.path
  }

  /// Resolves the bundled Lua runtime agent executable path.
  func resolvedRuntimeAgentPath() -> String? {
    let fileManager = FileManager.default

    if let executableURL = Bundle.main.executableURL {
      let siblingPath =
        executableURL
        .deletingLastPathComponent()
        .appendingPathComponent("EasyBarLuaRuntime")
        .path

      if fileManager.isExecutableFile(atPath: siblingPath) {
        return siblingPath
      }
    }

    let buildCandidate = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
      .appendingPathComponent(".build", isDirectory: true)
      .appendingPathComponent("debug", isDirectory: true)
      .appendingPathComponent("EasyBarLuaRuntime")
      .path

    if fileManager.isExecutableFile(atPath: buildCandidate) {
      return buildCandidate
    }

    logger.error("EasyBarLuaRuntime not found")
    return nil
  }

  /// Logs one Lua runtime launch request.
  func logLaunch(context: LaunchContext) {
    logger.debug("starting lua runtime")
    logger.debug("lua runtime agent", .field("path", context.runtimeAgentPath))
    logger.debug("lua binary", .field("path", context.luaPath))
    logger.debug("lua socket", .field("path", context.luaSocketPath))
    logger.debug("lua script", .field("path", context.runtimePath))
    logger.debug("widgets path", .field("path", context.widgetsPath))
    logger.debug("lua env keys", .field("keys", context.environment.keys.sorted()))
  }

  /// Spawns one Lua runtime process with a dedicated process group assigned at spawn time.
  func spawnProcess(context: LaunchContext, resources: LaunchResources) throws -> Int32 {
    let arguments = [
      context.runtimeAgentPath,
      context.luaSocketPath,
      context.luaPath,
      context.runtimePath,
      context.widgetsPath,
      String(context.defaultCommandTimeoutSeconds),
      String(context.defaultCommandMaxOutputBytes),
    ]

    var environment = ProcessInfo.processInfo.environment
    environment.merge(context.environment) { _, configuredValue in configuredValue }
    environment["EASYBAR_LUA_TRANSPORT_TOKEN"] = context.transportAuthenticationToken

    let pid = try ProcessSpawnSupport.spawn(
      executablePath: context.runtimeAgentPath,
      arguments: arguments,
      environment: environment,
      standardErrorFileDescriptor: resources.error.fileHandleForWriting.fileDescriptor,
      closeFileDescriptors: [resources.error.fileHandleForReading.fileDescriptor],
      createProcessGroup: true
    )

    try? resources.error.fileHandleForWriting.close()
    return pid
  }

  /// Installs exit observation for the spawned Lua child.
  func installTerminationSource(for pid: Int32) {
    let previousTask = state.withLock { state -> Task<Void, Never>? in
      let previousTask = state.terminationTask
      state.terminationTask = nil
      return previousTask
    }
    previousTask?.cancel()

    let task = DetachedTask.run(priority: .utility) { [weak self] in
      guard let self else { return }
      let observation = ProcessWaitSupport.wait(processIdentifier: pid)
      guard !Task.isCancelled else { return }
      self.handleTermination(pid: pid, observation: observation)
    }

    let installed = state.withLock { state -> Bool in
      guard case .running(let processIdentifier, _, _) = state.lifecycle,
        processIdentifier == pid
      else {
        return false
      }
      state.terminationTask = task
      return true
    }

    if !installed {
      task.cancel()
    }
  }

  /// Handles one observed Lua runtime termination.
  func handleTermination(pid: Int32, observation: ProcessWaitObservation) {
    let reason: Termination.Reason
    switch observation {
    case .running:
      return
    case .terminated(_, let terminationReason):
      reason = terminationReason
      logTermination(pid: pid, reason: terminationReason)
    case .failed(let errnoValue):
      if errnoValue != ECHILD {
        logger.warn(
          "failed to reap lua runtime",
          .field("pid", pid),
          .field("errno", errnoValue)
        )
      }
      reason = .reapFailed(errno: errnoValue)
    }

    guard let delivery = clearTrackedProcessIfMatching(pid: pid) else { return }
    delivery.handler?(
      Termination(
        processIdentifier: pid,
        reason: reason,
        wasRequested: delivery.wasRequested
      )
    )
  }

  /// Converts one raw Darwin wait status into the shared termination reason.
  func terminationReason(status: Int32) -> Termination.Reason {
    ProcessWaitSupport.decode(status: status)
  }

  /// Logs one Lua runtime termination reason.
  private func logTermination(pid processIdentifier: Int32, reason: Termination.Reason) {
    switch reason {
    case .exited(let code) where code == 0:
      logger.debug(
        "lua runtime exited",
        .field("pid", processIdentifier),
        .field("code", code)
      )
    case .exited(let code):
      logger.warn(
        "lua runtime exited",
        .field("pid", processIdentifier),
        .field("code", code)
      )
    case .signaled(let signal):
      logger.warn(
        "lua runtime terminated by signal",
        .field("pid", processIdentifier),
        .field("signal", signal)
      )
    case .unknown(let status):
      logger.warn(
        "lua runtime terminated",
        .field("pid", processIdentifier),
        .field("status", status)
      )
    case .reapFailed(let errnoValue):
      logger.warn(
        "failed to reap lua runtime",
        .field("pid", processIdentifier),
        .field("errno", errnoValue)
      )
    }
  }

  /// Closes all launch resources after a failed spawn attempt.
  func closeLaunchResourcesAfterFailedSpawn(_ resources: LaunchResources) {
    try? resources.error.fileHandleForReading.close()
    try? resources.error.fileHandleForWriting.close()
  }

  /// Returns the Lua runtime environment with app config and resolved theme values.
  private func luaRuntimeEnvironment(config: ConfigSnapshot) -> [String: String] {
    var environment = config.app.environment
      .merging(config.luaThemeEnvironment()) { _, themeValue in themeValue }
    environment[SharedEnvironmentKeys.luaWidgetPackagesDirectory] =
      WidgetPackageStore.activeDirectory(
        in: SharedPathDefaults.defaultWidgetPackagesPath()
      ).path
    return environment
  }
}
