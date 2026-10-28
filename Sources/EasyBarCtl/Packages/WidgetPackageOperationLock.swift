import Darwin
import Foundation

/// Calls the BSD advisory-lock function without colliding with Darwin's `flock` structure.
@_silgen_name("flock")
func easybarAdvisoryFlock(_ descriptor: Int32, _ operation: Int32) -> Int32

/// Serializes package metadata and filesystem changes across independent CLI processes.
final class WidgetPackageOperationLock {
  /// The open descriptor whose advisory lock is held for this object's lifetime.
  private let descriptor: Int32

  /// Acquires an exclusive package-directory lock, creating its private lock file if needed.
  private init(packagesDirectory: URL, fileManager: FileManager) throws {
    try fileManager.createDirectory(at: packagesDirectory, withIntermediateDirectories: true)
    let lockPath = packagesDirectory.appending(path: ".package-operation.lock").path
    let fd = Darwin.open(lockPath, O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, mode_t(0o600))
    guard fd >= 0 else {
      throw Self.lockError(path: lockPath, operation: "open")
    }
    guard easybarAdvisoryFlock(fd, LOCK_EX) == 0 else {
      let error = Self.lockError(path: lockPath, operation: "acquire")
      _ = Darwin.close(fd)
      throw error
    }
    descriptor = fd
  }

  /// Releases the advisory lock and its associated descriptor.
  deinit {
    _ = easybarAdvisoryFlock(descriptor, LOCK_UN)
    _ = Darwin.close(descriptor)
  }

  /// Runs one synchronous package operation while holding the cross-process lock.
  static func withExclusiveAccess<Result>(
    to packagesDirectory: URL,
    fileManager: FileManager,
    operation: () throws -> Result
  ) throws -> Result {
    let lock = try WidgetPackageOperationLock(
      packagesDirectory: packagesDirectory,
      fileManager: fileManager
    )
    defer { withExtendedLifetime(lock) {} }
    return try operation()
  }

  /// Runs one asynchronous package operation while holding the cross-process lock.
  static func withExclusiveAccess<Result>(
    to packagesDirectory: URL,
    fileManager: FileManager,
    operation: () async throws -> Result
  ) async throws -> Result {
    let lock = try WidgetPackageOperationLock(
      packagesDirectory: packagesDirectory,
      fileManager: fileManager
    )
    defer { withExtendedLifetime(lock) {} }
    return try await operation()
  }

  /// Returns a contextual error for opening or acquiring the package lock.
  private static func lockError(path: String, operation: String) -> WidgetPackageError {
    let reason = String(cString: strerror(errno))
    return .installConflict("could not \(operation) package lock at \(path): \(reason)")
  }
}
