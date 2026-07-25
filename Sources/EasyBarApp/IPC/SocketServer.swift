import EasyBarShared
import Foundation

/// Unix socket server used to receive external triggers.
///
/// Lifecycle methods (`start`, `reloadConfiguration`, and `stop`) and
/// `broadcastMetrics` must be called from one serialized execution context.
/// Production code enforces this by owning the server inside
/// `RuntimeCoordinator`, an actor. Transport callbacks may arrive on
/// background threads, but they do not mutate the server's lifecycle state.
final class SocketServer: @unchecked Sendable {
  enum ReloadOutcome: Equatable, Sendable {
    case unchanged
    case rebound
    case failed(requestedPath: String)

    var succeeded: Bool {
      if case .failed = self { return false }
      return true
    }
  }
  /// Concrete line-delimited socket transport used by the server.
  private typealias Transport = LineSocketServerTransport<
    IPC.Request,
    IPC.Request,
    IPC.Message
  >

  /// Logger used for socket-server diagnostics.
  private let logger: ProcessLogger
  /// Shared runtime metrics collector.
  private let metricsCoordinator: MetricsCoordinator

  /// Active socket transport instance.
  private var transport: Transport
  /// Current Unix-domain socket path.
  private var socketPath: String
  /// Handler invoked for accepted non-metrics commands.
  private var commandHandler: (@Sendable (IPC.Command) -> Void)?
  /// Handler invoked for config validation requests.
  private var validateConfigHandler: (@Sendable (String?) async -> IPC.Message)?
  /// Handler invoked for native inbox queries and mutations.
  private var inboxHandler: (@Sendable (IPC.InboxRequest) async -> IPC.Message)?
  /// Whether the socket server has already been started.
  private var started = false

  /// Creates a socket server bound to the configured socket path.
  init(
    logger: ProcessLogger,
    socketPath: String = SharedPathDefaults.easyBarSocketPath(
      in: resolvedRuntimeDirectory()
    ),
    metricsCoordinator: MetricsCoordinator = MetricsCoordinator.shared
  ) {
    self.logger = logger
    self.socketPath = socketPath
    self.metricsCoordinator = metricsCoordinator
    transport = Self.makeTransport(
      socketPath: socketPath,
      metricsCoordinator: metricsCoordinator,
      logger: logger.child("transport")
    )
    Self.installLiveLogSink(logger: logger, transport: transport)
  }

  /// Starts the socket listener.
  @discardableResult
  func start(
    handler: @escaping @Sendable (IPC.Command) -> Void,
    validateConfigHandler: @escaping @Sendable (String?) async -> IPC.Message,
    inboxHandler: @escaping @Sendable (IPC.InboxRequest) async -> IPC.Message = { _ in
      .rejected(message: "inbox control unavailable")
    }
  ) -> Bool {
    guard !started else { return true }

    commandHandler = handler
    self.validateConfigHandler = validateConfigHandler
    self.inboxHandler = inboxHandler

    let didStart = startTransport(
      transport,
      handler: handler,
      validateConfigHandler: validateConfigHandler,
      inboxHandler: inboxHandler
    )
    started = didStart
    return didStart
  }

  /// Reloads the socket server when the configured socket path changed.
  @discardableResult
  func reloadConfiguration(socketPath updatedSocketPath: String) -> ReloadOutcome {
    if updatedSocketPath == socketPath {
      guard !started else { return .unchanged }
      guard let commandHandler else { return .failed(requestedPath: updatedSocketPath) }

      let activeValidateConfigHandler: @Sendable (String?) async -> IPC.Message =
        validateConfigHandler ?? { _ in
          .rejected(message: "config validation unavailable")
        }
      let activeInboxHandler: @Sendable (IPC.InboxRequest) async -> IPC.Message =
        inboxHandler ?? { _ in .rejected(message: "inbox control unavailable") }

      let didStart = startTransport(
        transport,
        handler: commandHandler,
        validateConfigHandler: activeValidateConfigHandler,
        inboxHandler: activeInboxHandler
      )
      started = didStart
      return didStart ? .rebound : .failed(requestedPath: updatedSocketPath)
    }

    guard let commandHandler else {
      socketPath = updatedSocketPath
      transport = Self.makeTransport(
        socketPath: updatedSocketPath,
        metricsCoordinator: metricsCoordinator,
        logger: logger.child("transport")
      )
      Self.installLiveLogSink(logger: logger, transport: transport)
      return .rebound
    }

    logger.info(
      "restarting socket server",
      .field("old_path", "\(socketPath)"),
      .field("new_path", "\(updatedSocketPath)")
    )

    let replacementTransport = Self.makeTransport(
      socketPath: updatedSocketPath,
      metricsCoordinator: metricsCoordinator,
      logger: logger.child("transport")
    )

    let activeValidateConfigHandler: @Sendable (String?) async -> IPC.Message =
      validateConfigHandler ?? { _ in
        .rejected(message: "config validation unavailable")
      }
    let activeInboxHandler: @Sendable (IPC.InboxRequest) async -> IPC.Message =
      inboxHandler ?? { _ in .rejected(message: "inbox control unavailable") }

    let didStart = startTransport(
      replacementTransport,
      handler: commandHandler,
      validateConfigHandler: activeValidateConfigHandler,
      inboxHandler: activeInboxHandler
    )

    guard didStart else {
      logger.error(
        "socket server reload failed; keeping existing listener",
        .field("active_path", "\(socketPath)"),
        .field("requested_path", "\(updatedSocketPath)")
      )
      return .failed(requestedPath: updatedSocketPath)
    }

    let previousTransport = transport
    transport = replacementTransport
    Self.installLiveLogSink(logger: logger, transport: replacementTransport)
    socketPath = updatedSocketPath
    started = true

    previousTransport.stop()
    SynchronousTask.run {
      await self.metricsCoordinator.resetStreaming()
    }
    return .rebound
  }

  /// Stops the socket listener.
  func stop() {
    started = false
    commandHandler = nil
    validateConfigHandler = nil
    inboxHandler = nil

    transport.stop()
    SynchronousTask.run {
      await self.metricsCoordinator.resetStreaming()
    }
  }

  /// Broadcasts one metrics payload to all active stream subscribers.
  func broadcastMetrics(_ snapshot: IPC.MetricsSnapshot) {
    let message = IPC.Message.metrics(snapshot)

    for subscriber in transport.subscribersSnapshot() {
      guard case .metrics(watch: true) = subscriber.subscriber else { continue }
      if !transport.send(message, to: subscriber.fd) {
        _ = transport.removeSubscriber(fd: subscriber.fd)
      }
    }
  }

  /// Installs the shared bounded live-log sink for one active transport.
  private static func installLiveLogSink(
    logger: ProcessLogger,
    transport: Transport
  ) {
    ProcessLogSocketSink.install(
      logger: logger,
      transport: transport,
      subscription: { request in
        guard case .logs(let subscription) = request else { return nil }
        return subscription
      },
      response: { event in IPC.Message.logRecord(event) }
    )
  }

  /// Starts one concrete transport with the retained request handlers.
  private func startTransport(
    _ transport: Transport,
    handler: @escaping @Sendable (IPC.Command) -> Void,
    validateConfigHandler: @escaping @Sendable (String?) async -> IPC.Message,
    inboxHandler: @escaping @Sendable (IPC.InboxRequest) async -> IPC.Message
  ) -> Bool {
    transport.start { [weak self, weak transport] clientFD, request in
      guard let self, let transport else {
        return .close
      }

      return self.handle(
        clientFD: clientFD,
        request: request,
        handler: handler,
        validateConfigHandler: validateConfigHandler,
        inboxHandler: inboxHandler,
        transport: transport
      )
    }
  }

  /// Handles one decoded IPC request.
  private func handle(
    clientFD: Int32,
    request: IPC.Request,
    handler: @escaping @Sendable (IPC.Command) -> Void,
    validateConfigHandler: @escaping @Sendable (String?) async -> IPC.Message,
    inboxHandler: @escaping @Sendable (IPC.InboxRequest) async -> IPC.Message,
    transport: Transport
  ) -> Transport.ClientDisposition {
    logger.debug("socket dispatching command '\(request.command.rawValue)'")

    switch request {
    case .metrics(let watch):
      return handleMetricsRequest(
        clientFD: clientFD,
        watch: watch,
        request: request,
        transport: transport
      )

    case .logs:
      return handleLogsRequest(
        clientFD: clientFD,
        request: request,
        transport: transport
      )

    case .validateConfig(let configPath):
      return handleValidateConfigRequest(
        clientFD: clientFD,
        configPath: configPath,
        validateConfigHandler: validateConfigHandler,
        transport: transport
      )

    case .inbox(let request):
      let response = SynchronousTask.run { await inboxHandler(request) }
      _ = transport.send(response, to: clientFD)
      return .close

    case .command(let command):
      _ = transport.send(.accepted, to: clientFD)
      handler(command)
      return .close
    }
  }

  /// Handles one metrics request.
  private func handleMetricsRequest(
    clientFD: Int32,
    watch: Bool,
    request: IPC.Request,
    transport: Transport
  ) -> Transport.ClientDisposition {
    let snapshot = SynchronousTask.run {
      await self.metricsCoordinator.snapshot()
    }
    let sent = transport.send(.metrics(snapshot), to: clientFD)

    guard sent else {
      return .close
    }

    guard watch else {
      return .close
    }

    SynchronousTask.run {
      await self.metricsCoordinator.addStreamingSubscriber(fd: clientFD)
    }

    guard transport.addSubscriber(request, for: clientFD) else {
      SynchronousTask.run {
        await self.metricsCoordinator.removeStreamingSubscriber(fd: clientFD)
      }
      return .close
    }

    return .keepOpen
  }

  /// Registers one bounded live log subscriber.
  private func handleLogsRequest(
    clientFD: Int32,
    request: IPC.Request,
    transport: Transport
  ) -> Transport.ClientDisposition {
    guard transport.addSubscriber(request, for: clientFD) else {
      return .close
    }
    guard transport.send(.logSubscribed, to: clientFD) else {
      _ = transport.removeSubscriber(fd: clientFD)
      return .close
    }
    return .keepOpen
  }

  /// Handles one config validation request using the app's real config validator.
  private func handleValidateConfigRequest(
    clientFD: Int32,
    configPath: String?,
    validateConfigHandler: @escaping @Sendable (String?) async -> IPC.Message,
    transport: Transport
  ) -> Transport.ClientDisposition {
    let response = SynchronousTask.run {
      await validateConfigHandler(configPath)
    }
    _ = transport.send(response, to: clientFD)
    return .close
  }

  /// Creates one transport bound to the given socket path.
  private static func makeTransport(
    socketPath: String,
    metricsCoordinator: MetricsCoordinator,
    logger: ProcessLogger
  ) -> Transport {
    Transport(
      socketPath: socketPath,
      serverLabel: "easybar",
      logger: logger,
      onClientRejected: {
        Task { await metricsCoordinator.recordSocketClientRejection() }
      },
      onSubscriberRemoved: { fd in
        SynchronousTask.run {
          await metricsCoordinator.removeStreamingSubscriber(fd: fd)
        }
      }
    )
  }
}
