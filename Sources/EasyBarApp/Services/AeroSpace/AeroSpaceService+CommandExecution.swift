import EasyBarShared
import Foundation

// MARK: - AeroSpace Command Execution

extension AeroSpaceService {
  /// Runs the AeroSpace CLI while the service lifecycle remains active.
  func runAeroSpace(arguments: [String]) async -> String? {
    guard isActive, !Task.isCancelled else { return nil }

    let output = await commandRunner.run(arguments: arguments)

    guard isActive, !Task.isCancelled else { return nil }
    return output
  }

  /// Resolves a stable app identity from bundle path or name.
  static func resolvedAppID(name: String, bundlePath: String?) -> String {
    guard let bundlePath, !bundlePath.isEmpty else {
      return name
    }

    return bundlePath
  }

  /// Returns whether the service is still allowed to execute queued work.
  func shouldExecute(generation: UInt64) -> Bool {
    withLock { state in
      state.running && state.active && !state.consumers.isEmpty && state.generation == generation
    }
  }

  /// Returns whether this token is still the newest refresh in the active lifecycle.
  func shouldExecute(refreshToken: AeroSpaceRefreshToken) -> Bool {
    withLock { state in
      state.running
        && state.active
        && !state.consumers.isEmpty
        && state.pendingRefreshToken == refreshToken
        && state.refreshSequence.isCurrent(refreshToken, generation: state.generation)
    }
  }

  /// Returns the current refresh generation.
  func currentGeneration() -> UInt64 {
    withLock { $0.generation }
  }

  /// Runs one closure while holding the service state lock.
  func withLock<T>(_ body: @Sendable (inout CoordinationState) -> T) -> T {
    coordination.withLock(body)
  }
}
