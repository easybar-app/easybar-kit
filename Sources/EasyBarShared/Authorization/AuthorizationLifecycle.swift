import Foundation

/// Owns one generation-scoped authorization callback and retry scheduler.
///
/// Every call to `start` creates a new session. Work captured by an older
/// session can still finish, but it can no longer notify callers or interfere
/// with retries scheduled by the current session.
public final class AuthorizationLifecycle: @unchecked Sendable {
  /// One active authorization generation.
  public final class Session: @unchecked Sendable {
    private let lock = NSRecursiveLock()
    private var active = true
    private var onChange: (() -> Void)?
    fileprivate let retryBackoff: AuthorizationRetryBackoff

    /// Creates a session.
    fileprivate init(
      onChange: @escaping () -> Void,
      retryBackoff: AuthorizationRetryBackoff
    ) {
      self.onChange = onChange
      self.retryBackoff = retryBackoff
    }

    /// Returns whether this session has not been replaced or stopped.
    fileprivate var isActive: Bool {
      lock.lock()
      defer { lock.unlock() }
      return active
    }

    /// Invalidates callbacks and pending retry work for this session.
    fileprivate func deactivate() {
      lock.lock()
      active = false
      onChange = nil
      lock.unlock()

      retryBackoff.reset()
    }

    /// Invokes the callback only while the session remains active.
    fileprivate func notifyIfActive() {
      lock.lock()
      defer { lock.unlock() }

      guard active else { return }
      onChange?()
    }
  }

  /// Stores state data.
  private struct State {
    /// The current session for this state.
    var currentSession: Session?
  }

  private let logger: ProcessLogger
  private let delays: [TimeInterval]
  private let sleeper: any AsyncSleeper
  private let state = LockedState(State())

  /// Creates one lifecycle with the standard authorization retry sequence.
  public init(
    logger: ProcessLogger,
    delays: [TimeInterval] = [1, 2, 3, 5, 8, 13, 21, 34, 55, 60],
    sleeper: any AsyncSleeper = TaskSleeper()
  ) {
    self.logger = logger
    self.delays = delays
    self.sleeper = sleeper
  }

  /// Starts a new generation and invalidates any previous one.
  @discardableResult
  public func start(onChange: @escaping () -> Void) -> Session {
    let session = Session(
      onChange: onChange,
      retryBackoff: AuthorizationRetryBackoff(
        delays: delays,
        logger: logger.child("retry_backoff"),
        sleeper: sleeper
      )
    )

    let previous = state.withLock { state -> Session? in
      let previous = state.currentSession
      state.currentSession = session
      return previous
    }
    previous?.deactivate()

    return session
  }

  /// Stops the current generation and invalidates all of its pending work.
  public func stop() {
    let session = state.withLock { state -> Session? in
      let session = state.currentSession
      state.currentSession = nil
      return session
    }
    session?.deactivate()
  }

  /// Returns the current active session, when authorization handling is running.
  public func currentSession() -> Session? {
    let session = state.withLock { $0.currentSession }
    guard session?.isActive == true else { return nil }
    return session
  }

  /// Returns whether the supplied session is still the current generation.
  public func isCurrent(_ session: Session) -> Bool {
    let currentSession = state.withLock { $0.currentSession }
    return currentSession === session && session.isActive
  }

  /// Invokes the current session callback when it has not been invalidated.
  public func notify(_ session: Session) {
    guard isCurrent(session) else { return }
    session.notifyIfActive()
  }

  /// Cancels pending retry work for only the supplied generation.
  public func resetRetry(for session: Session) {
    session.retryBackoff.reset()
  }

  /// Schedules retry work that is discarded if the session becomes stale.
  @discardableResult
  public func scheduleRetry(
    for session: Session,
    _ action: @escaping @Sendable (Session) -> Void
  ) -> Bool {
    guard isCurrent(session) else { return false }

    session.retryBackoff.schedule { [weak self, weak session] in
      guard let self, let session, self.isCurrent(session) else { return }
      action(session)
    }
    return true
  }
}
