import Darwin
import Dispatch
import Foundation

/// Serves line-delimited JSON requests over a Unix domain socket and optionally tracks subscribers.
///
/// Each accepted connection owns a close-once descriptor and a bounded serial
/// writer. Slow subscribers therefore cannot block unrelated clients, queued
/// broadcasts cannot grow without limit, and stale worker cleanup cannot close a
/// descriptor that the operating system has already reused.
public final class LineSocketServerTransport<
  Subscriber: Sendable,
  Request: Decodable & Sendable,
  Response: Encodable & Sendable
>: @unchecked Sendable {
  /// One currently connected subscriber entry.
  public struct SubscriberEntry {
    public let fd: Int32
    public let subscriber: Subscriber

    /// Creates one subscriber entry.
    public init(fd: Int32, subscriber: Subscriber) {
      self.fd = fd
      self.subscriber = subscriber
    }
  }

  /// Describes what should happen to a client socket after one request was handled.
  public enum ClientDisposition: Sendable {
    case close
    case keepOpen
  }

  private final class ClientConnection: @unchecked Sendable {
    let identifier: UInt64
    let writer: BoundedSocketWriter

    var fd: Int32 { writer.fd }

    init(
      fd: Int32,
      identifier: UInt64,
      label: String,
      writeTimeout: TimeInterval,
      maxPendingMessages: Int,
      maxPendingBytes: Int
    ) {
      self.identifier = identifier
      self.writer = BoundedSocketWriter(
        fd: fd,
        label: label,
        writeTimeout: writeTimeout,
        maxPendingMessages: maxPendingMessages,
        maxPendingBytes: maxPendingBytes
      )
    }

    func close() {
      writer.close()
    }
  }

  private struct SubscriberRegistration {
    let connection: ClientConnection
    let subscriber: Subscriber
  }

  private struct State {
    var listener: OwnedUnixSocketListener?
    var running = false
    var generation: UInt64 = 0
    var acceptThread: Thread?
    var nextClientIdentifier: UInt64 = 0
    var clients: [Int32: ClientConnection] = [:]
    var requestClientFDs: Set<Int32> = []
    var lastOverloadLogTime: TimeInterval = 0
    var subscribers: [Int32: SubscriberRegistration] = [:]
  }

  private struct StopSnapshot {
    let wasRunning: Bool
    let listener: OwnedUnixSocketListener?
    let clients: [ClientConnection]
    let subscriberFDs: [Int32]
  }

  private enum Readiness {
    case ready
    case timedOut
    case closed
  }

  private let socketPath: String
  private let serverLabel: String
  private let logger: ProcessLogger
  private let onSubscriberRemoved: ((Int32) -> Void)?
  private let onClientRejected: (() -> Void)?
  private let initialRequestTimeout: TimeInterval
  private let maxRequestBytes: Int
  private let maxConcurrentClients: Int
  private let maxSubscribers: Int
  private let workerDrainTimeout: TimeInterval
  private let writeTimeout: TimeInterval
  private let maxPendingWritesPerClient: Int
  private let maxPendingWriteBytesPerClient: Int
  private let workerGroup = DispatchGroup()
  private let state = LockedState(State())

  /// Creates a new Unix socket server transport.
  public init(
    socketPath: String,
    serverLabel: String,
    logger: ProcessLogger,
    initialRequestTimeout: TimeInterval = 5,
    maxRequestBytes: Int = LineDelimitedJSONDecoder<Request>.defaultMaxLineBytes,
    maxConcurrentClients: Int = 32,
    maxSubscribers: Int = 128,
    workerDrainTimeout: TimeInterval = 2,
    writeTimeout: TimeInterval = 1,
    maxPendingWritesPerClient: Int = 64,
    maxPendingWriteBytesPerClient: Int = 1024 * 1024,
    onClientRejected: (() -> Void)? = nil,
    onSubscriberRemoved: ((Int32) -> Void)? = nil
  ) {
    self.socketPath = socketPath
    self.serverLabel = serverLabel
    self.logger = logger
    self.initialRequestTimeout = normalizedSocketTimeout(initialRequestTimeout)
    self.maxRequestBytes = max(1, maxRequestBytes)
    self.maxConcurrentClients = max(1, maxConcurrentClients)
    self.maxSubscribers = max(1, maxSubscribers)
    self.workerDrainTimeout = workerDrainTimeout.isFinite ? max(0, workerDrainTimeout) : 2
    self.writeTimeout = normalizedSocketTimeout(writeTimeout, fallback: 1)
    self.maxPendingWritesPerClient = max(1, maxPendingWritesPerClient)
    self.maxPendingWriteBytesPerClient = max(1, maxPendingWriteBytesPerClient)
    self.onSubscriberRemoved = onSubscriberRemoved
    self.onClientRejected = onClientRejected
  }

  /// Stops the server before deallocation.
  deinit {
    stop()
  }

  /// Starts listening and dispatches decoded requests to the handler.
  @discardableResult
  public func start(
    _ handler: @escaping @Sendable (Int32, Request) -> ClientDisposition
  ) -> Bool {
    let generation = state.withLock { state -> UInt64? in
      guard !state.running else { return nil }
      state.running = true
      state.generation &+= 1
      return state.generation
    }

    guard let generation else { return false }

    guard let listener = makeListeningSocket() else {
      state.withLock { state in
        if state.listener == nil, state.generation == generation {
          state.running = false
        }
      }
      return false
    }

    let shouldCancel = state.withLock { state -> Bool in
      guard state.running, state.generation == generation else { return true }
      state.listener = listener
      return false
    }

    if shouldCancel {
      closeListeningUnixSocket(listener)
      return false
    }

    logger.info(
      "\(serverLabel) listening",
      .field("socket_path", socketPath),
    )

    workerGroup.enter()
    let thread = Thread { [weak self, workerGroup] in
      defer { workerGroup.leave() }
      self?.acceptLoop(listener: listener, generation: generation, handler: handler)
    }
    thread.name = "\(serverLabel) socket accept"
    thread.qualityOfService = .utility

    let shouldStartThread = state.withLock { state -> Bool in
      guard
        state.running,
        state.generation == generation,
        state.listener?.fd == listener.fd
      else { return false }
      state.acceptThread = thread
      return true
    }

    if shouldStartThread {
      thread.start()
    } else {
      workerGroup.leave()
      closeListeningUnixSocket(listener)
    }

    return shouldStartThread
  }

  /// Stops the server, closes connected clients, and removes only its own socket path.
  public func stop() {
    let snapshot = state.withLock { state -> StopSnapshot in
      let snapshot = StopSnapshot(
        wasRunning: state.running,
        listener: state.listener,
        clients: Array(state.clients.values),
        subscriberFDs: Array(state.subscribers.keys)
      )

      state.running = false
      state.generation &+= 1
      state.listener = nil
      state.acceptThread = nil
      state.clients.removeAll()
      state.requestClientFDs.removeAll()
      state.subscribers.removeAll()
      return snapshot
    }

    guard snapshot.wasRunning else { return }

    for connection in snapshot.clients {
      connection.close()
    }

    for subscriberFD in snapshot.subscriberFDs {
      onSubscriberRemoved?(subscriberFD)
    }

    if let listener = snapshot.listener {
      closeListeningUnixSocket(listener)
    }

    if workerGroup.wait(timeout: .now() + workerDrainTimeout) == .timedOut {
      logger.warn("\(serverLabel) socket workers did not drain before shutdown timeout")
    }
    logger.info(
      "\(serverLabel) stopped",
      .field("socket_path", socketPath),
    )
  }

  /// Sends one encoded response to the given active client.
  @discardableResult
  public func send(_ response: Response, to clientFD: Int32) -> Bool {
    guard let connection = currentConnection(for: clientFD) else { return false }
    guard let data = encode(response) else { return false }

    if let error = connection.writer.writeSynchronously(data) {
      logWriteFailure(error, fd: connection.fd)
      closeClientConnection(connection)
      return false
    }
    return true
  }

  /// Enqueues one response for an active client without waiting for socket I/O.
  @discardableResult
  public func enqueue(_ response: Response, to clientFD: Int32) -> Bool {
    guard let connection = currentConnection(for: clientFD) else { return false }
    guard let data = encode(response) else { return false }

    let accepted = connection.writer.enqueue(data) { [weak self, weak connection] error in
      guard let self, let connection, let error else { return }
      self.logWriteFailure(error, fd: connection.fd)
      self.closeClientConnection(connection)
    }

    guard accepted else {
      closeClientConnection(connection)
      return false
    }
    return true
  }

  /// Sends one terminal response and closes the client after the handler returns.
  public func closeAfterSending(_ response: Response, to clientFD: Int32) -> ClientDisposition {
    if !send(response, to: clientFD) {
      logger.debug(
        "\(serverLabel) terminal response was not delivered",
        .field("fd", clientFD)
      )
    }
    return .close
  }

  /// Sends a terminal response before scheduling its acknowledged action on the main actor.
  public func closeAfterSending(
    _ response: Response,
    to clientFD: Int32,
    then action: @escaping @MainActor @Sendable () -> Void
  ) -> ClientDisposition {
    guard send(response, to: clientFD) else { return .close }
    Task { @MainActor in
      action()
    }
    return .close
  }

  /// Adds or replaces one subscriber without consuming the short-lived request-client budget.
  @discardableResult
  public func addSubscriber(_ subscriber: Subscriber, for fd: Int32) -> Bool {
    let added = state.withLock { state -> Bool in
      guard state.running, let connection = state.clients[fd] else { return false }
      if state.subscribers[fd] == nil {
        guard state.subscribers.count < maxSubscribers else { return false }
        state.requestClientFDs.remove(fd)
      }
      state.subscribers[fd] = SubscriberRegistration(
        connection: connection,
        subscriber: subscriber
      )
      return true
    }

    guard added else { return false }

    logger.debug(
      "\(serverLabel) subscriber added",
      .field("fd", fd),
    )
    return true
  }

  /// Removes one subscriber and closes its socket.
  @discardableResult
  public func removeSubscriber(fd: Int32) -> Bool {
    guard let registration = state.withLock({ $0.subscribers[fd] }) else { return false }
    closeClientConnection(registration.connection)
    return true
  }

  /// Returns a stable snapshot of current subscribers.
  public func subscribersSnapshot() -> [SubscriberEntry] {
    state.withLock { state in
      state.subscribers.values.map {
        SubscriberEntry(fd: $0.connection.fd, subscriber: $0.subscriber)
      }
    }
  }

  /// Enqueues one derived response per subscriber without blocking other clients.
  public func broadcast(_ response: (Subscriber) -> Response) {
    let registrations = state.withLock { Array($0.subscribers.values) }

    for registration in registrations {
      guard let data = encode(response(registration.subscriber)) else { continue }
      let connection = registration.connection
      let accepted = connection.writer.enqueue(data) { [weak self, weak connection] error in
        guard let self, let connection, let error else { return }
        self.logWriteFailure(error, fd: connection.fd)
        self.closeClientConnection(connection)
      }

      if !accepted {
        logger.warn(
          "\(serverLabel) subscriber write queue is full",
          .field("fd", connection.fd),
          .field("max_messages", maxPendingWritesPerClient),
          .field("max_bytes", maxPendingWriteBytesPerClient)
        )
        closeClientConnection(connection)
      }
    }
  }

  /// Creates and starts the listening socket.
  private func makeListeningSocket() -> OwnedUnixSocketListener? {
    do {
      return try makeOwnedListeningUnixSocket(
        at: socketPath,
        backlog: 8,
        onChmodFailure: { [logger, serverLabel, socketPath] errnoValue in
          logger.warn(
            "\(serverLabel) chmod failed",
            .field("path", socketPath),
            .field("errno", errnoValue),
          )
        }
      )
    } catch {
      logger.error(
        "\(serverLabel) listen socket setup failed",
        .field("path", socketPath),
        .field("error", error),
      )
      return nil
    }
  }

  /// Accepts client connections until the server stops.
  private func acceptLoop(
    listener: OwnedUnixSocketListener,
    generation: UInt64,
    handler: @escaping @Sendable (Int32, Request) -> ClientDisposition
  ) {
    while isActiveServer(listener: listener, generation: generation) {
      let clientFD = accept(listener.fd, nil, nil)
      if clientFD < 0 {
        if errno == EINTR { continue }
        if !isActiveServer(listener: listener, generation: generation) { break }

        logger.debug(
          "\(serverLabel) accept failed",
          .field("errno", errno),
        )
        continue
      }

      guard configureNoSigPipe(fd: clientFD), configureNonBlocking(fd: clientFD) else {
        logger.error(
          "\(serverLabel) failed to configure accepted socket",
          .field("fd", clientFD),
          .field("errno", errno)
        )
        close(clientFD)
        continue
      }

      let registration = registerClientFD(clientFD, generation: generation)
      guard let connection = registration.connection else {
        onClientRejected?()
        if registration.shouldLogOverload {
          logger.warn(
            "\(serverLabel) concurrent request-client limit reached",
            .field("limit", maxConcurrentClients)
          )
        }
        Darwin.shutdown(clientFD, SHUT_RDWR)
        close(clientFD)
        continue
      }

      workerGroup.enter()
      let clientThread = Thread { [weak self, workerGroup, connection] in
        defer { workerGroup.leave() }
        self?.handleClient(connection, handler: handler)
      }
      clientThread.name = "\(serverLabel) socket client"
      clientThread.qualityOfService = .utility
      clientThread.start()
    }
  }

  /// Reads requests until the client disconnects and invokes the handler for each line.
  private func handleClient(
    _ connection: ClientConnection,
    handler: @escaping @Sendable (Int32, Request) -> ClientDisposition
  ) {
    var lineDecoder = LineDelimitedJSONDecoder<Request>(maxLineBytes: maxRequestBytes)
    var buffer = [UInt8](repeating: 0, count: 4096)
    var isWaitingForInitialRequest = true
    let initialRequestDeadline = monotonicPollDeadline(after: initialRequestTimeout)

    while isActiveConnection(connection) {
      let deadline =
        isWaitingForInitialRequest
        ? initialRequestDeadline
        : monotonicPollDeadline(after: 1)
      switch waitForReadable(
        on: connection,
        deadline: deadline,
        initialRequest: isWaitingForInitialRequest
      ) {
      case .ready:
        break
      case .timedOut where !isWaitingForInitialRequest:
        continue
      case .timedOut, .closed:
        closeClientConnection(connection)
        return
      }

      let count = buffer.withUnsafeMutableBytes { rawBuffer -> Int in
        guard let baseAddress = rawBuffer.baseAddress else { return -1 }
        return Darwin.read(connection.fd, baseAddress, rawBuffer.count)
      }

      if count > 0 {
        let result = handleDecodedRequests(
          lineDecoder.append(buffer.prefix(count)),
          connection: connection,
          handler: handler
        )

        if result.handledRequest {
          isWaitingForInitialRequest = false
        }

        if result.disposition == .close {
          closeClientConnection(connection)
          return
        }
        continue
      }

      if count == 0 {
        closeClientConnection(connection)
        return
      }

      if errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK {
        continue
      }

      logger.debug(
        "\(serverLabel) client read failed",
        .field("fd", connection.fd),
        .field("errno", errno),
      )
      closeClientConnection(connection)
      return
    }
  }

  /// Dispatches decoded requests and returns the resulting socket disposition.
  private func handleDecodedRequests(
    _ results: [Result<Request, Error>],
    connection: ClientConnection,
    handler: @escaping @Sendable (Int32, Request) -> ClientDisposition
  ) -> (disposition: ClientDisposition, handledRequest: Bool) {
    for result in results {
      guard isActiveConnection(connection) else { return (.close, false) }

      switch result {
      case .success(let request):
        let disposition = handler(connection.fd, request)
        if disposition == .close {
          return (.close, true)
        }

      case .failure(let error):
        logger.warn(
          "\(serverLabel) request decode failed",
          .field("error", error),
        )
        return (.close, false)
      }
    }

    return (.keepOpen, !results.isEmpty)
  }

  /// Waits for socket input while retaining a finite initial-request deadline.
  private func waitForReadable(
    on connection: ClientConnection,
    deadline: UInt64,
    initialRequest: Bool
  ) -> Readiness {
    var descriptor = pollfd(fd: connection.fd, events: Int16(POLLIN), revents: 0)

    while isActiveConnection(connection) {
      let result = poll(&descriptor, 1, remainingPollMilliseconds(until: deadline))
      if result > 0 {
        let events = Int32(descriptor.revents)
        if (events & POLLIN) != 0 { return .ready }
        if (events & (POLLERR | POLLHUP | POLLNVAL)) != 0 { return .closed }
        continue
      }

      if result < 0 && errno == EINTR { continue }
      if result == 0 {
        if initialRequest {
          logger.debug(
            "\(serverLabel) initial request timed out",
            .field("fd", connection.fd)
          )
        }
        return .timedOut
      }
      return .closed
    }

    return .closed
  }

  /// Tracks one accepted request client when the server is still running.
  private func registerClientFD(
    _ fd: Int32,
    generation: UInt64
  ) -> (connection: ClientConnection?, shouldLogOverload: Bool) {
    state.withLock { state in
      guard state.running, state.generation == generation else { return (nil, false) }
      guard state.requestClientFDs.count < maxConcurrentClients else {
        let now = ProcessInfo.processInfo.systemUptime
        let shouldLog = now - state.lastOverloadLogTime >= 5
        if shouldLog { state.lastOverloadLogTime = now }
        return (nil, shouldLog)
      }

      state.nextClientIdentifier &+= 1
      let connection = ClientConnection(
        fd: fd,
        identifier: state.nextClientIdentifier,
        label: "easybar.\(serverLabel).socket-writer.\(state.nextClientIdentifier)",
        writeTimeout: writeTimeout,
        maxPendingMessages: maxPendingWritesPerClient,
        maxPendingBytes: maxPendingWriteBytesPerClient
      )
      state.clients[fd] = connection
      state.requestClientFDs.insert(fd)
      return (connection, false)
    }
  }

  /// Closes one client only when it is still the registered object for its fd.
  private func closeClientConnection(_ connection: ClientConnection) {
    let removed = state.withLock { state -> (close: Bool, subscriber: Bool) in
      guard let current = state.clients[connection.fd], current === connection else {
        return (false, false)
      }
      state.clients.removeValue(forKey: connection.fd)
      state.requestClientFDs.remove(connection.fd)
      let subscriber = state.subscribers.removeValue(forKey: connection.fd) != nil
      return (true, subscriber)
    }

    guard removed.close else { return }
    connection.close()

    if removed.subscriber {
      logger.debug(
        "\(serverLabel) subscriber removed",
        .field("fd", connection.fd),
      )
      onSubscriberRemoved?(connection.fd)
    }
  }

  /// Returns the active connection object for one descriptor.
  private func currentConnection(for fd: Int32) -> ClientConnection? {
    state.withLock { $0.clients[fd] }
  }

  /// Returns whether one connection object is still current.
  private func isActiveConnection(_ connection: ClientConnection) -> Bool {
    state.withLock { state in
      state.running && state.clients[connection.fd] === connection
    }
  }

  /// Returns whether one accept loop still owns the active server run.
  private func isActiveServer(
    listener: OwnedUnixSocketListener,
    generation: UInt64
  ) -> Bool {
    state.withLock {
      $0.running && $0.generation == generation && $0.listener?.fd == listener.fd
    }
  }

  /// Encodes one response as a sorted newline-delimited JSON record.
  private func encode(_ response: Response) -> Data? {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    encoder.dateEncodingStrategy = .iso8601

    do {
      return try encoder.encode(response) + Data([0x0A])
    } catch {
      logger.error(
        "\(serverLabel) response encode failed",
        .field("error", error),
      )
      return nil
    }
  }

  /// Records a concrete socket write failure.
  private func logWriteFailure(_ error: UnixSocketWriteError, fd: Int32) {
    logger.warn(
      "\(serverLabel) response write failed",
      .field("fd", fd),
      .field("error", String(describing: error))
    )
  }
}
