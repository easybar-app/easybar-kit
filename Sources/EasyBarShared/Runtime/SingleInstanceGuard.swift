import Darwin
import Foundation

/// Defines the supported single instance lock result values.
public enum SingleInstanceLockResult: Equatable {
  case acquired(lockPath: String)
  case alreadyRunning(lockPath: String)
  case failed(lockPath: String, reason: String)
}

/// Coordinates single instance guard state and behavior.
public final class SingleInstanceGuard {
  private var lockFileHandle: FileHandle?

  /// Creates one single-instance guard.
  public init() {}

  /// Closes the held lock file.
  deinit {
    lockFileHandle?.closeFile()
  }

  /// Tries to acquire an exclusive non-blocking lock for the current process.
  @discardableResult
  public func acquireLock(at path: String) -> SingleInstanceLockResult {
    let url = URL(fileURLWithPath: path)
    let directoryURL = url.deletingLastPathComponent()

    do {
      try FileManager.default.createDirectory(
        at: directoryURL,
        withIntermediateDirectories: true,
        attributes: nil
      )
    } catch {
      return .failed(lockPath: path, reason: "create_directory_failed:\(error)")
    }

    let fd = open(url.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
    guard fd >= 0 else {
      return .failed(lockPath: path, reason: "open_failed:\(String(cString: strerror(errno)))")
    }

    guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
      let lockError = errno
      close(fd)

      if lockError == EWOULDBLOCK {
        return .alreadyRunning(lockPath: path)
      }

      return .failed(
        lockPath: path,
        reason: "lock_failed:\(String(cString: strerror(lockError)))"
      )
    }

    let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)

    if let data = "\(getpid())\n".data(using: .utf8) {
      do {
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: data)
        try handle.synchronize()
      } catch {
        // Keep the lock even if PID writing fails.
      }
    }

    lockFileHandle?.closeFile()
    lockFileHandle = handle
    return .acquired(lockPath: path)
  }

  /// Resolves the default lock path for one named process and acquires it.
  @discardableResult
  public func acquireLock(
    processName: String,
    directory: String? = nil
  ) -> SingleInstanceLockResult {
    let lockPath = defaultSingleInstanceLockPath(
      processName: processName,
      directory: directory
    )

    return acquireLock(at: lockPath)
  }
}

/// Returns the default lock path for one named process.
public func defaultSingleInstanceLockPath(processName: String, directory: String? = nil) -> String {
  let baseDirectory =
    expandedPath(directory?.trimmingCharacters(in: .whitespacesAndNewlines))
    ?? FileManager.default.temporaryDirectory.path

  return URL(fileURLWithPath: baseDirectory, isDirectory: true)
    .appendingPathComponent("\(processName).lock")
    .path
}
