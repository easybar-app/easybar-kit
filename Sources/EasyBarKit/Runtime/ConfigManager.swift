import EasyBarShared
import Foundation

/// Actor-owned access to config mutation and runtime-facing config snapshots.
actor ConfigManager {
  struct ValidationResult: Sendable {
    /// Resolved path of the validated config file.
    let configPath: String
    /// User-facing validation error when validation failed.
    let errorMessage: String?
    /// Non-fatal configuration warnings discovered during validation.
    let warnings: [String]
  }

  struct LuaCommandSettings: Sendable {
    let timeoutSeconds: TimeInterval
    let maxOutputBytes: Int
    let maxAsyncJobs: Int
    let environment: [String: String]
  }

  /// Result of one config load or reload attempt.
  struct ReloadResult: Sendable {
    /// Whether reload completed without validation errors.
    let succeeded: Bool
    /// User-facing reload error when reload failed.
    let errorMessage: String?
    /// Active immutable config snapshot after the load attempt.
    let snapshot: ConfigSnapshot
    /// Immutable config snapshot active before the load attempt.
    let previousSnapshot: ConfigSnapshot
  }

  /// Live config store that remains the only mutation boundary.
  private let config: Config
  private var previousLoadedState: Config.LoadedState?
  /// Creates one config manager for a live config store.
  init(config: Config = Config.makeUnloadedConfig()) {
    self.config = config
  }

  /// Loads the active config during app startup and returns a stable result.
  func loadInitialConfig() async -> ReloadResult {
    await MainActor.run {
      let previousSnapshot = config.snapshot()
      let error = config.loadInitialState()
      let snapshot = config.snapshot()
      return Self.makeReloadResult(
        error: error,
        snapshot: snapshot,
        previousSnapshot: previousSnapshot
      )
    }
  }

  /// Reloads the active config and returns a stable result.
  func reload() async -> ReloadResult {
    let loadedState = await MainActor.run { config.loadedStateSnapshot() }
    previousLoadedState = loadedState

    return await MainActor.run {
      let previousSnapshot = config.snapshot()
      let error = config.reload()
      let snapshot = config.snapshot()
      return Self.makeReloadResult(
        error: error,
        snapshot: snapshot,
        previousSnapshot: previousSnapshot
      )
    }
  }

  /// Restores a previously captured live config snapshot.
  func restorePreviousState() async {
    guard let previousLoadedState else { return }
    await MainActor.run {
      config.applyLoadedState(previousLoadedState)
    }
    self.previousLoadedState = nil
  }

  /// Discards rollback state after the runtime successfully activates a reload.
  func discardPreviousState() {
    previousLoadedState = nil
  }

  /// Returns the current active immutable config snapshot.
  func snapshot() async -> ConfigSnapshot {
    await MainActor.run {
      config.snapshot()
    }
  }

  /// Validates config without mutating live runtime state.
  func validateConfig(configPathOverride: String? = nil) async -> ValidationResult {
    await MainActor.run {
      do {
        let result = try ConfigValidator.validate(configPathOverride: configPathOverride)
        return ValidationResult(
          configPath: result.configPath,
          errorMessage: nil,
          warnings: result.warnings
        )
      } catch {
        return ValidationResult(
          configPath: Self.resolvedValidationConfigPath(configPathOverride),
          errorMessage: Self.validationErrorMessage(error),
          warnings: []
        )
      }
    }
  }

  /// Returns whether config watching is enabled.
  func watchConfigFileEnabled() async -> Bool {
    await MainActor.run {
      config.watchConfigFile
    }
  }

  /// Returns the active config path.
  func configPath() async -> String {
    await MainActor.run {
      config.configPath
    }
  }

  /// Returns the active EasyBar socket path.
  func easyBarSocketPath() async -> String {
    await MainActor.run {
      config.easyBarSocketPath
    }
  }

  /// Returns the current minimum log level.
  func loggingLevel() async -> ProcessLogLevel {
    await MainActor.run {
      config.loggingLevel
    }
  }

  /// Returns whether file logging is enabled.
  func loggingEnabled() async -> Bool {
    await MainActor.run {
      config.loggingEnabled
    }
  }

  /// Returns the configured logging directory.
  func loggingDirectory() async -> String {
    await MainActor.run {
      config.loggingDirectory
    }
  }

  /// Returns the current Lua command execution settings.
  func luaCommandSettings() async -> LuaCommandSettings {
    await MainActor.run {
      Self.luaCommandSettings(from: config.snapshot())
    }
  }

  /// Builds one reload result from a stable snapshot.
  private static func makeReloadResult(
    error: (any Error)?,
    snapshot: ConfigSnapshot,
    previousSnapshot: ConfigSnapshot
  ) -> ReloadResult {
    ReloadResult(
      succeeded: error == nil,
      errorMessage: error.map { String(describing: $0) },
      snapshot: snapshot,
      previousSnapshot: previousSnapshot
    )
  }

  /// Returns Lua command settings from an immutable config snapshot.
  private static func luaCommandSettings(from snapshot: ConfigSnapshot) -> LuaCommandSettings {
    LuaCommandSettings(
      timeoutSeconds: snapshot.app.luaCommandLimits.timeoutSeconds,
      maxOutputBytes: snapshot.app.luaCommandLimits.maxOutputBytes,
      maxAsyncJobs: snapshot.app.luaCommandLimits.maxAsyncJobs,
      environment: luaCommandEnvironment(from: snapshot)
    )
  }

  /// Returns the environment used by Lua shell commands.
  private static func luaCommandEnvironment(from snapshot: ConfigSnapshot) -> [String: String] {
    ProcessInfo.processInfo.environment.merging(snapshot.app.environment) { _, configuredValue in
      configuredValue
    }
  }

  /// Returns the resolved config path used for validation status and errors.
  private static func resolvedValidationConfigPath(_ configPathOverride: String?) -> String {
    if let resolvedOverride = expandedPath(configPathOverride) {
      return resolvedOverride
    }

    return expandedEnvironmentPath(named: SharedEnvironmentKeys.configPath)
      ?? SharedPathDefaults.defaultConfigPath().path
  }

  /// Returns a concise user-facing validation error message.
  private static func validationErrorMessage(_ error: any Error) -> String {
    if let localizedError = error as? LocalizedError,
      let description = localizedError.errorDescription,
      !description.isEmpty
    {
      return description
    }

    return "\(error)"
  }
}
