import Darwin
import EasyBarShared
import Foundation

/// Serves network-agent socket requests.
@MainActor
final class NetworkSocketServer {
  /// Active subscription state for one connected client.
  private enum Subscriber: Sendable {
    /// Fields requested by a network snapshot subscriber.
    case fields([NetworkAgentField])
    /// Filter used when streaming live process logs.
    case logs(IPC.LogSubscription)
  }

  /// Disposition returned after handling one client request.
  private typealias ClientDisposition = LineSocketServerTransport<
    Subscriber,
    NetworkAgentRequest,
    NetworkAgentMessage
  >.ClientDisposition

  private var provider: NetworkSnapshotProvider?
  private let componentName: String
  private let socketPath: String
  private let appVersion: String
  private let allowUnauthorizedNonSensitiveFields: Bool
  private let logger: ProcessLogger
  /// Host callback invoked after a restart acknowledgement has been sent.
  private let onRestartRequested: @MainActor () -> Void
  private let transport: LineSocketServerTransport<Subscriber, NetworkAgentRequest, NetworkAgentMessage>

  /// Builds the network socket server for one socket path.
  init(
    componentName: String,
    socketPath: String,
    appVersion: String,
    allowUnauthorizedNonSensitiveFields: Bool,
    logger: ProcessLogger,
    onRestartRequested: @escaping @MainActor () -> Void
  ) {
    self.componentName = componentName
    self.socketPath = socketPath
    self.appVersion = appVersion
    self.allowUnauthorizedNonSensitiveFields = allowUnauthorizedNonSensitiveFields
    self.logger = logger
    self.onRestartRequested = onRestartRequested
    transport = LineSocketServerTransport(
      socketPath: socketPath,
      serverLabel: componentName,
      logger: logger.child("transport"),
    )

    ProcessLogSocketSink.install(
      logger: logger,
      transport: transport,
      subscription: { subscriber in
        guard case .logs(let subscription) = subscriber else { return nil }
        return subscription
      },
      response: { event in
        NetworkAgentMessage(kind: .logRecord, logRecord: event)
      }
    )
  }

  /// Starts accepting network agent requests.
  @discardableResult
  func start(provider: NetworkSnapshotProvider) -> Bool {
    self.provider = provider
    let started = transport.start { [weak self] clientFD, request in
      SynchronousTask.runOnMainActor { [weak self] in
        guard let self else { return .close }
        return self.handleClient(clientFD, request: request)
      }
    }

    if !started {
      self.provider = nil
    }
    return started
  }

  /// Stops the network socket server.
  func stop() {
    transport.stop()
    provider = nil
  }

  /// Broadcasts the latest requested fields to all subscribers.
  func broadcastSnapshots() {
    guard let provider else { return }

    for entry in transport.subscribersSnapshot() {
      guard case .fields(let fields) = entry.subscriber else { continue }
      _ = transport.enqueue(
        makeResponseMessage(from: responseFields(for: fields, provider: provider)),
        to: entry.fd
      )
    }
  }

  /// Handles one network agent client request.
  private func handleClient(
    _ clientFD: Int32,
    request: NetworkAgentRequest
  ) -> ClientDisposition {
    logger.debug(
      "\(componentName) request",
      .field("fd", clientFD),
      .field("command", request.command.rawValue),
    )

    switch request.command {
    case .ping:
      return sendPong(to: clientFD)
    case .version:
      return sendVersion(to: clientFD)
    case .fetch:
      return handleFetch(to: clientFD, request: request)
    case .subscribe:
      return handleSubscribe(to: clientFD, request: request)
    case .logs:
      return handleLogs(to: clientFD, request: request)
    case .restart:
      return handleRestart(to: clientFD)
    }
  }

  /// Acknowledges the request before allowing the host app to terminate.
  private func handleRestart(to clientFD: Int32) -> ClientDisposition {
    return transport.closeAfterSending(NetworkAgentMessage(kind: .restarting), to: clientFD) {
      [onRestartRequested] in
      onRestartRequested()
    }
  }

  /// Sends a pong response.
  private func sendPong(to clientFD: Int32) -> ClientDisposition {
    return transport.closeAfterSending(NetworkAgentMessage(kind: .pong), to: clientFD)
  }

  /// Sends the network-agent version response.
  private func sendVersion(to clientFD: Int32) -> ClientDisposition {
    return transport.closeAfterSending(
      NetworkAgentMessage(
        kind: .version,
        version: NetworkAgentVersion(
          appVersion: appVersion,
          protocolVersion: easyBarIPCProtocolVersion
        )
      ),
      to: clientFD
    )
  }

  /// Handles a one-shot field fetch.
  private func handleFetch(
    to clientFD: Int32,
    request: NetworkAgentRequest
  ) -> ClientDisposition {
    guard let provider else {
      return sendError(to: clientFD, code: .providerUnavailable)
    }

    guard let fields = validatedFields(from: request) else {
      return sendError(to: clientFD, code: .missingFields)
    }

    let response = responseFields(for: fields, provider: provider)
    return transport.closeAfterSending(makeResponseMessage(from: response), to: clientFD)
  }

  /// Handles a live field subscription.
  private func handleSubscribe(
    to clientFD: Int32,
    request: NetworkAgentRequest
  ) -> ClientDisposition {
    guard let provider else {
      return sendError(to: clientFD, code: .providerUnavailable)
    }

    guard let fields = validatedFields(from: request) else {
      return sendError(to: clientFD, code: .missingFields)
    }

    guard transport.addSubscriber(.fields(fields), for: clientFD) else {
      logger.warn("\(componentName) subscriber rejected", .field("fd", clientFD))
      return .close
    }
    logger.info(
      "\(componentName) subscriber registered",
      .field("fd", clientFD),
    )

    guard transport.send(NetworkAgentMessage(kind: .subscribed), to: clientFD) else {
      _ = transport.removeSubscriber(fd: clientFD)
      return .close
    }

    let response = responseFields(for: fields, provider: provider)
    guard transport.send(makeResponseMessage(from: response), to: clientFD) else {
      _ = transport.removeSubscriber(fd: clientFD)
      return .close
    }

    return .keepOpen
  }

  /// Handles one bounded live-log subscription.
  private func handleLogs(
    to clientFD: Int32,
    request: NetworkAgentRequest
  ) -> ClientDisposition {
    guard let subscription = request.logSubscription else {
      return sendError(
        to: clientFD,
        code: .unknown,
        message: "Missing live log subscription."
      )
    }

    guard transport.addSubscriber(.logs(subscription), for: clientFD) else {
      return .close
    }
    guard transport.send(NetworkAgentMessage(kind: .logSubscribed), to: clientFD) else {
      _ = transport.removeSubscriber(fd: clientFD)
      return .close
    }
    return .keepOpen
  }

  /// Sends a structured network-agent error response.
  private func sendError(
    to clientFD: Int32,
    code: NetworkAgentErrorCode,
    message: String? = nil
  ) -> ClientDisposition {
    _ = transport.send(
      NetworkAgentMessage(kind: .error, errorCode: code, message: message),
      to: clientFD
    )
    return .close
  }

  /// Returns the validated field list for one request.
  private func validatedFields(from request: NetworkAgentRequest) -> [NetworkAgentField]? {
    guard let fields = request.fields, !fields.isEmpty else { return nil }
    return fields
  }

  /// Returns one field response or a permission error for the current auth state.
  private func responseFields(
    for fields: [NetworkAgentField],
    provider: NetworkSnapshotProvider
  ) -> (
    fields: [String: NetworkAgentFieldValue]?,
    statuses: [String: NetworkAgentFieldStatus]?,
    errorCode: NetworkAgentErrorCode?
  ) {
    let response = provider.responseFields(
      for: fields,
      allowUnauthorizedFieldsWithoutLocation: allowUnauthorizedNonSensitiveFields
    )
    return (response.values, response.statuses, response.errorCode)
  }

  /// Builds one network-agent message from a field response result.
  private func makeResponseMessage(
    from response: (
      fields: [String: NetworkAgentFieldValue]?,
      statuses: [String: NetworkAgentFieldStatus]?,
      errorCode: NetworkAgentErrorCode?
    )
  ) -> NetworkAgentMessage {
    if let fields = response.fields {
      return NetworkAgentMessage(
        kind: .fields,
        fields: fields,
        fieldStatuses: response.statuses
      )
    }

    return NetworkAgentMessage(
      kind: .error,
      fieldStatuses: response.statuses,
      errorCode: response.errorCode ?? .unknown
    )
  }

}
