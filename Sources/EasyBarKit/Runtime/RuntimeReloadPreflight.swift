import EasyBarShared

/// Applies the reversible boundary changes required before activating a reloaded configuration.
enum RuntimeReloadPreflight {
  /// Rebinds the socket and instance lock, restoring the previous config when either step fails.
  static func apply(
    result: ConfigManager.ReloadResult,
    configManager: ConfigManager,
    socketServer: SocketServer,
    logger: ProcessLogger,
    rebindInstanceLock: @escaping @MainActor @Sendable (String) -> Bool
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

    guard result.snapshot.app.lockDirectory != result.previousSnapshot.app.lockDirectory else {
      return true
    }

    let acquired = await rebindInstanceLock(result.snapshot.app.lockDirectory)
    guard acquired else {
      let rollbackOutcome = socketServer.reloadConfiguration(socketPath: previousSocketPath)
      await configManager.restorePreviousState()
      logger.error(
        "config reload rolled back after instance lock failure",
        .field("lock_directory", result.snapshot.app.lockDirectory),
        .field("socket_rollback_succeeded", rollbackOutcome.succeeded)
      )
      return false
    }

    return true
  }
}
