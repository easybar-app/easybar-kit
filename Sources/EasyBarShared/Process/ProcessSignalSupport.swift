import Darwin

/// Result of signaling a dedicated process group with an optional leader fallback.
public struct ProcessSignalDelivery: Equatable, Sendable {
  /// Whether the delivered option is enabled for this process signal delivery.
  public let delivered: Bool
  /// The process group error for this process signal delivery.
  public let processGroupError: Int32?
  /// The process error for this process signal delivery.
  public let processError: Int32?

  /// Returns whether every attempted target was already absent.
  public var targetWasMissing: Bool {
    guard !delivered else { return false }
    let errors = [processGroupError, processError].compactMap { $0 }
    return !errors.isEmpty && errors.allSatisfy { $0 == ESRCH }
  }
}

/// Checked signal delivery shared by long-lived and short-lived process owners.
public enum ProcessSignalSupport {
  /// Signals a process group first and optionally falls back to the leader process.
  @discardableResult
  public static func send(
    _ signal: Int32,
    processIdentifier: pid_t,
    processGroupIdentifier: pid_t?,
    fallbackToProcess: Bool = true
  ) -> ProcessSignalDelivery {
    var processGroupError: Int32?

    if let processGroupIdentifier, processGroupIdentifier > 0 {
      if kill(-processGroupIdentifier, signal) == 0 {
        return ProcessSignalDelivery(
          delivered: true,
          processGroupError: nil,
          processError: nil
        )
      }
      processGroupError = errno
    }

    guard fallbackToProcess, processIdentifier > 0 else {
      return ProcessSignalDelivery(
        delivered: false,
        processGroupError: processGroupError,
        processError: nil
      )
    }

    if kill(processIdentifier, signal) == 0 {
      return ProcessSignalDelivery(
        delivered: true,
        processGroupError: processGroupError,
        processError: nil
      )
    }

    return ProcessSignalDelivery(
      delivered: false,
      processGroupError: processGroupError,
      processError: errno
    )
  }

  /// Returns whether a dedicated process group still has at least one member.
  public static func isRunning(processGroupIdentifier: pid_t) -> Bool {
    guard processGroupIdentifier > 0 else { return false }
    if kill(-processGroupIdentifier, 0) == 0 {
      return true
    }
    return errno == EPERM
  }

  /// Returns whether one process currently exists or is inaccessible to this user.
  public static func isRunning(processIdentifier: pid_t) -> Bool {
    guard processIdentifier > 0 else { return false }
    if kill(processIdentifier, 0) == 0 {
      return true
    }
    return errno == EPERM
  }
}
