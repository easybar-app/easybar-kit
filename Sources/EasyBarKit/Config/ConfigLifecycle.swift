import EasyBarShared
import Foundation

extension Config {
  /// One fully loaded config state produced off to the side before swapping live values.
  struct LoadedState: Sendable {
    let snapshot: ConfigSnapshot
    let registeredDirectories: [String: RequiredDirectory]
    let warnings: [String]
  }

  /// Captures all live configuration state needed for an exact rollback.
  func loadedStateSnapshot() -> LoadedState {
    LoadedState(
      snapshot: snapshot(),
      registeredDirectories: registeredDirectories,
      warnings: configWarnings
    )
  }

  /// Loads config from disk during app startup.
  @discardableResult
  func loadInitialState() -> (any Error)? {
    do {
      applyLoadedState(try Self.makeLoadedState())
      loadFailureState = nil
      objectWillChange.send()
      return nil
    } catch {
      loadFailureState = LoadFailureState(error: error, context: .initialLoad)
      objectWillChange.send()
      return error
    }
  }

  /// Reloads config from disk and returns one validation error when reload fails.
  @discardableResult
  func reload() -> (any Error)? {
    let fallbackSnapshot = snapshot()
    let fallbackDirectories = registeredDirectories
    let fallbackWarnings = configWarnings

    do {
      applyLoadedState(try Self.makeLoadedState())
      loadFailureState = nil
      objectWillChange.send()
      return nil
    } catch {
      apply(fallbackSnapshot)
      registeredDirectories = fallbackDirectories
      configWarnings = fallbackWarnings
      loadFailureState = LoadFailureState(error: error, context: .reloadKeptPreviousConfig)
      objectWillChange.send()
      return error
    }
  }

  /// Swaps one fully loaded config state into the live store.
  func applyLoadedState(_ state: LoadedState) {
    apply(state.snapshot)
    registeredDirectories = state.registeredDirectories
    configWarnings = state.warnings
  }

  /// Builds one staged config state without mutating the live singleton.
  private static func makeLoadedState(
    configPathOverride: String? = nil,
    validateOnly: Bool = false
  ) throws -> LoadedState {
    let staged = Self.makeUnloadedConfig(configPathOverride: configPathOverride)
    staged.resetToDefaults()
    try staged.load(validateOnly: validateOnly)

    return LoadedState(
      snapshot: staged.snapshot(),
      registeredDirectories: staged.registeredDirectories,
      warnings: staged.configWarnings
    )
  }

  /// Validates config without mutating the live singleton or creating directories.
  static func validate(configPathOverride: String? = nil) throws -> LoadedState {
    return try makeLoadedState(
      configPathOverride: configPathOverride,
      validateOnly: true
    )
  }
}
