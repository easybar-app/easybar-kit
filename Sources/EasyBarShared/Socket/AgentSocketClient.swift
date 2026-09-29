import Darwin
import Foundation

/// Shared newline-delimited client transport used by app-side and helper-process agent clients.
///
/// Every connection owns a deadline-bound writer. Shutdown invalidates and
/// shuts down the socket before queued writes drain, preventing a peer that has
/// stopped reading from deadlocking reconnect or application teardown.
public final class AgentSocketClient<
  Request: Encodable & Sendable,
  Message: Decodable & Sendable
>: @unchecked Sendable {
  /// Coordinates connection state and behavior.
  private final class Connection: @unchecked Sendable {
    let identifier: UInt64
    let writer: BoundedSocketWriter

    var fd: Int32 { writer.fd }

    /// Creates a connection.
    init(fd: Int32, identifier: UInt64, label: String, writeTimeout: TimeInterval) {
      self.identifier = identifier
      self.writer = BoundedSocketWriter(
        fd: fd,
        label: "easybar.\(label).socket-writer.\(identifier)",
        writeTimeout: writeTimeout,
        maxPendingMessages: 8,
        maxPendingBytes: 256 * 1024
      )
    }
  }

  /// Stores state data.
  private struct State {
    /// Whether this state is running.
    var running = false
    /// Whether the reconnect suspended option is enabled for this state.
    var reconnectSuspended = false
    /// The connection thread for this state.
    var connectionThread: Thread?
    /// The next reconnect delay override for this state.
    var nextReconnectDelayOverride: TimeInterval?
    /// The stable identifier for this state.
    var nextConnectionID: UInt64 = 0
    /// The current connection generation for this state.
    var currentConnectionGeneration: UInt64 = 0
    /// The connection for this state.
    var connection: Connection?
  }

  /// Stores stop snapshot data.
  private struct StopSnapshot {
    /// The connection for this stop snapshot.
    let connection: Connection?
    /// The stable identifier for this stop snapshot.
    let connectionID: UInt64
    /// Whether the should notify disconnect option is enabled for this stop snapshot.
    let shouldNotifyDisconnect: Bool
  }

  private let label: String
  private let socketPath: () -> String
  private let subscribeRequest: () -> Request
  private let handleMessage: (Message, UInt64) -> Void
  private let clearState: (UInt64) -> Void
  private let onConnected: (() -> Void)?
  private let onDisconnected: (() -> Void)?
  private let onDecodedMessage: (() -> Void)?
  private let onDecodeError: (() -> Void)?
  private let logger: ProcessLogger
  private let reconnectScheduler: BackoffScheduler
  private let writeTimeout: TimeInterval
  private let state = LockedState(State())

  /// Creates one shared agent client transport.
  public init(
    label: String,
    socketPath: @escaping () -> String,
    subscribeRequest: @escaping () -> Request,
    handleMessage: @escaping (Message, UInt64) -> Void,
    clearState: @escaping (UInt64) -> Void,
    onConnected: (() -> Void)? = nil,
    onDisconnected: (() -> Void)? = nil,
    onDecodedMessage: (() -> Void)? = nil,
    onDecodeError: (() -> Void)? = nil,
    writeTimeout: TimeInterval = 1,
    logger: ProcessLogger
  ) {
    self.label = label
    self.socketPath = socketPath
    self.subscribeRequest = subscribeRequest
    self.handleMessage = handleMessage
    self.clearState = clearState
    self.onConnected = onConnected
    self.onDisconnected = onDisconnected
    self.onDecodedMessage = onDecodedMessage
    self.onDecodeError = onDecodeError
    self.writeTimeout = normalizedSocketTimeout(writeTimeout, fallback: 1)
    self.logger = logger
    self.reconnectScheduler = BackoffScheduler(
      label: "\(label) reconnect",
      delays: [2, 5, 10, 30],
      logger: logger
    )
  }

  /// Returns whether the client currently has an open socket.
  public var isConnected: Bool {
    state.withLock { $0.running && $0.connection != nil }
  }

  /// Returns whether a callback generation still belongs to the current client run.
  public func isCurrentConnectionGeneration(_ connectionID: UInt64) -> Bool {
    state.withLock { state in
      state.running && state.currentConnectionGeneration == connectionID
    }
  }

  /// Starts the client connection loop.
  public func start() {
    let shouldConnect = state.withLock { state -> Bool in
      guard !state.running else { return false }
      state.running = true
      state.reconnectSuspended = false
      return true
    }

    guard shouldConnect else { return }
    reconnectScheduler.cancel()
    connect()
  }

  /// Stops the client and clears published state.
  public func stop() {
    let snapshot = state.withLock { state -> StopSnapshot in
      state.running = false
      state.reconnectSuspended = false
      state.nextReconnectDelayOverride = nil

      let connection = state.connection
      state.connection = nil
      state.connectionThread = nil
      state.nextConnectionID &+= 1
      state.currentConnectionGeneration = state.nextConnectionID

      return StopSnapshot(
        connection: connection,
        connectionID: connection?.identifier ?? state.nextConnectionID,
        shouldNotifyDisconnect: connection != nil
      )
    }

    reconnectScheduler.cancel()
    snapshot.connection?.writer.close()
    clearState(snapshot.connectionID)

    if snapshot.shouldNotifyDisconnect {
      onDisconnected?()
    }
  }

  /// Overrides the delay used for the next reconnect attempt.
  public func setNextReconnectDelay(_ delay: TimeInterval?) {
    state.withLock { state in
      state.nextReconnectDelayOverride = delay.flatMap {
        $0.isFinite ? max(0, $0) : nil
      }
    }
  }

  /// Suspends automatic reconnect attempts while preserving the active run.
  public func suspendReconnect() {
    let shouldCancel = state.withLock { state -> Bool in
      guard state.running else { return false }
      state.reconnectSuspended = true
      return true
    }

    if shouldCancel {
      reconnectScheduler.cancel()
    }
  }

  /// Resumes reconnects and immediately reconnects when no socket is active.
  public func resumeReconnect() {
    let resume = state.withLock { state -> (wasSuspended: Bool, shouldConnect: Bool) in
      guard state.running else { return (false, false) }

      let wasSuspended = state.reconnectSuspended
      state.reconnectSuspended = false
      let shouldConnect =
        wasSuspended && state.connection == nil && state.connectionThread == nil
      return (wasSuspended, shouldConnect)
    }

    guard resume.wasSuspended else { return }

    reconnectScheduler.cancel()
    if resume.shouldConnect {
      connect()
    }
  }

  /// Sends one fresh subscribe request through the active socket.
  public func refresh() {
    guard let connection = currentConnection() else { return }

    guard send(subscribeRequest(), to: connection) else {
      logger.warn("\(label) failed to send refresh request")
      handleDisconnect(connection)
      return
    }
  }

  /// Starts one connection attempt on a dedicated socket thread.
  private func connect() {
    let thread = Thread { [weak self] in
      self?.runConnectionAttempt()
    }
    thread.name = "\(label) socket client"
    thread.qualityOfService = .utility

    let shouldStart = state.withLock { state -> Bool in
      guard state.running else { return false }
      state.connectionThread = thread
      return true
    }

    if shouldStart {
      thread.start()
    }
  }

  /// Performs one connection attempt and read loop.
  private func runConnectionAttempt() {
    guard isRunning() else { return }

    let resolvedSocketPath = socketPath()
    guard let fd = openConnectedSocket(socketPath: resolvedSocketPath) else {
      scheduleReconnect()
      return
    }

    guard let connection = activateConnectedSocketFD(fd) else {
      Darwin.shutdown(fd, SHUT_RDWR)
      close(fd)
      return
    }

    onConnected?()
    logger.info(
      "\(label) connected",
      .field("socket", resolvedSocketPath),
    )

    guard send(subscribeRequest(), to: connection) else {
      logger.warn("\(label) failed to send subscribe request")
      handleDisconnect(connection)
      return
    }

    reconnectScheduler.resetDelay()
    readLoop(connection)
  }

  /// Reads newline-delimited messages until the socket disconnects.
  private func readLoop(_ connection: Connection) {
    var buffer = [UInt8](repeating: 0, count: 4096)
    var lineDecoder = LineDelimitedJSONDecoder<Message>()

    while isActiveConnection(connection) {
      guard waitForReadable(connection) else { break }

      let count = buffer.withUnsafeMutableBytes { rawBuffer -> Int in
        guard let baseAddress = rawBuffer.baseAddress else { return -1 }
        return Darwin.read(connection.fd, baseAddress, rawBuffer.count)
      }

      if count > 0 {
        handleDecodedMessages(
          lineDecoder.append(buffer.prefix(count)),
          connection: connection
        )
        continue
      }

      if count == 0 {
        handleDecodedMessages(lineDecoder.flush(), connection: connection)
        break
      }

      if errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK {
        continue
      }

      logger.debug(
        "\(label) read failed",
        .field("errno", errno),
      )
      break
    }

    handleDisconnect(connection)
  }

  /// Handles decoded message payloads and records decode failures.
  private func handleDecodedMessages(
    _ results: [Result<Message, Error>],
    connection: Connection
  ) {
    for result in results {
      guard isActiveConnection(connection) else { return }

      switch result {
      case .success(let message):
        onDecodedMessage?()
        guard isActiveConnection(connection) else { return }
        handleMessage(message, connection.identifier)

      case .failure(let error):
        onDecodeError?()
        logger.warn(
          "\(label) failed to decode message",
          .field("error", error),
        )
      }
    }
  }

  /// Handles one socket disconnect and schedules reconnect when still running.
  private func handleDisconnect(_ connection: Connection) {
    let wasActive = clearConnectedSocket(connection)
    guard wasActive else { return }

    connection.writer.close()
    clearState(connection.identifier)
    onDisconnected?()

    guard isRunning() else { return }

    logger.info("\(label) disconnected")
    scheduleReconnect()
  }

  /// Schedules one reconnect attempt.
  private func scheduleReconnect() {
    let reconnect = state.withLock { state -> (running: Bool, delayOverride: TimeInterval?) in
      guard state.running, !state.reconnectSuspended else { return (false, nil) }
      let delay = state.nextReconnectDelayOverride
      state.nextReconnectDelayOverride = nil
      return (true, delay)
    }

    guard reconnect.running else { return }
    reconnectScheduler.schedule(after: reconnect.delayOverride) { [weak self] in
      self?.connect()
    }
  }

  /// Returns whether the client is meant to be running.
  private func isRunning() -> Bool {
    state.withLock { $0.running }
  }

  /// Returns the currently active connection.
  private func currentConnection() -> Connection? {
    state.withLock { $0.connection }
  }

  /// Stores one newly connected socket when still running.
  private func activateConnectedSocketFD(_ fd: Int32) -> Connection? {
    let activation = state.withLock { state -> (Connection, Connection?)? in
      guard state.running else { return nil }

      state.nextConnectionID &+= 1
      let connection = Connection(
        fd: fd,
        identifier: state.nextConnectionID,
        label: label,
        writeTimeout: writeTimeout
      )
      let replacedConnection = state.connection
      state.connection = connection
      state.currentConnectionGeneration = connection.identifier
      return (connection, replacedConnection)
    }

    guard let activation else { return nil }
    activation.1?.writer.close()
    return activation.0
  }

  /// Clears the active connection if it still matches the given object.
  private func clearConnectedSocket(_ connection: Connection) -> Bool {
    state.withLock { state -> Bool in
      guard state.connection === connection else { return false }
      state.connection = nil
      state.connectionThread = nil
      return true
    }
  }

  /// Returns whether the object still represents the active connection.
  private func isActiveConnection(_ connection: Connection) -> Bool {
    state.withLock { state in
      state.running && state.connection === connection
    }
  }

  /// Opens one connected nonblocking Unix socket.
  private func openConnectedSocket(socketPath: String) -> Int32? {
    do {
      return try openConnectedUnixSocket(
        at: socketPath,
        timeout: 5,
        keepNonBlocking: true
      )
    } catch {
      logger.warn(
        "\(label) socket connection failed",
        .field("socket", socketPath),
        .field("error", error),
      )
      return nil
    }
  }

  /// Encodes and sends one request line.
  private func send(_ request: Request, to connection: Connection) -> Bool {
    guard isActiveConnection(connection) else {
      logger.debug("\(label) dropping stale socket write")
      return false
    }

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    encoder.dateEncodingStrategy = .iso8601

    do {
      let data = try encoder.encode(request) + Data([0x0A])
      if let error = connection.writer.writeSynchronously(data) {
        logger.warn(
          "\(label) request write failed",
          .field("error", String(describing: error))
        )
        return false
      }
      return true
    } catch {
      logger.warn(
        "\(label) failed to encode request",
        .field("error", error),
      )
      return false
    }
  }

  /// Waits for input while periodically checking connection ownership.
  private func waitForReadable(_ connection: Connection) -> Bool {
    var descriptor = pollfd(fd: connection.fd, events: Int16(POLLIN), revents: 0)

    while isActiveConnection(connection) {
      let result = poll(&descriptor, 1, 1_000)
      if result > 0 {
        let events = Int32(descriptor.revents)
        if (events & POLLIN) != 0 { return true }
        if (events & (POLLERR | POLLHUP | POLLNVAL)) != 0 { return false }
        continue
      }
      if result == 0 { continue }
      if errno == EINTR { continue }
      return false
    }
    return false
  }
}
