import Darwin
import Dispatch
import Foundation

/// Serializes writes for one nonblocking socket and bounds queued memory.
///
/// Closing marks the writer unusable and shuts the socket down immediately. The
/// descriptor itself is closed on the writer queue after in-flight work observes
/// the shutdown, so stale queued closures can never target a reused descriptor.
public final class BoundedSocketWriter: @unchecked Sendable {
  /// Stores state data.
  private struct State {
    /// Whether this state is closed.
    var isClosed = false
    /// Whether the close scheduled option is enabled for this state.
    var closeScheduled = false
    /// The pending messages for this state.
    var pendingMessages = 0
    /// The pending bytes for this state.
    var pendingBytes = 0
  }

  public let fd: Int32

  private let writeTimeout: TimeInterval
  private let maxPendingMessages: Int
  private let maxPendingBytes: Int
  private let queue: DispatchQueue
  private let queueKey = DispatchSpecificKey<UInt8>()
  private let state = LockedState(State())

  /// Creates one writer that assumes ownership of `fd`.
  public init(
    fd: Int32,
    label: String,
    writeTimeout: TimeInterval = 1,
    maxPendingMessages: Int = 128,
    maxPendingBytes: Int = 1024 * 1024
  ) {
    self.fd = fd
    self.writeTimeout = normalizedSocketTimeout(writeTimeout, fallback: 1)
    self.maxPendingMessages = max(1, maxPendingMessages)
    self.maxPendingBytes = max(1, maxPendingBytes)
    self.queue = DispatchQueue(label: label)
    queue.setSpecific(key: queueKey, value: 1)
  }

  /// Releases resources retained by this instance.
  deinit {
    close()
  }

  /// Returns whether the writer has begun closing.
  public var isClosed: Bool {
    state.withLock { $0.isClosed }
  }

  /// Writes one payload in queue order and returns its concrete failure, if any.
  public func writeSynchronously(_ data: Data) -> UnixSocketWriteError? {
    if DispatchQueue.getSpecific(key: queueKey) != nil {
      return writeIfOpen(data)
    }
    return queue.sync { writeIfOpen(data) }
  }

  /// Enqueues one payload when both message and byte budgets have capacity.
  @discardableResult
  public func enqueue(
    _ data: Data,
    completion: (@Sendable (UnixSocketWriteError?) -> Void)? = nil
  ) -> Bool {
    let reserved = state.withLock { state -> Bool in
      guard !state.isClosed else { return false }
      guard state.pendingMessages < maxPendingMessages else { return false }
      guard data.count <= maxPendingBytes - state.pendingBytes else { return false }
      state.pendingMessages += 1
      state.pendingBytes += data.count
      return true
    }
    guard reserved else { return false }

    queue.async { [self, data] in
      let result = writeIfOpen(data)
      state.withLock { state in
        state.pendingMessages = max(0, state.pendingMessages - 1)
        state.pendingBytes = max(0, state.pendingBytes - data.count)
      }
      completion?(result)
    }
    return true
  }

  /// Shuts down the connection and schedules one close after queued writers drain.
  public func close() {
    let shouldScheduleClose = state.withLock { state -> Bool in
      guard !state.closeScheduled else { return false }
      state.isClosed = true
      state.closeScheduled = true
      return true
    }
    guard shouldScheduleClose else { return }

    Darwin.shutdown(fd, SHUT_RDWR)
    queue.async { [fd] in
      Darwin.close(fd)
    }
  }

  /// Returns one snapshot of the current pending queue budgets for tests and diagnostics.
  public var pendingQueueUsage: (messages: Int, bytes: Int) {
    state.withLock { ($0.pendingMessages, $0.pendingBytes) }
  }

  /// Writes if open.
  private func writeIfOpen(_ data: Data) -> UnixSocketWriteError? {
    guard !state.withLock({ $0.isClosed }) else { return .closed }
    return writeAll(data, to: fd, timeout: writeTimeout)
  }
}
