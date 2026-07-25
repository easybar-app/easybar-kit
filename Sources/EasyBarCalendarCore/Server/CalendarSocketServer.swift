import Darwin
import EasyBarShared
import Foundation

/// Serves calendar agent requests over a line-delimited socket protocol.
@MainActor
final class CalendarSocketServer {
  /// Active subscription state for one connected client.
  private enum Subscriber: Sendable {
    /// Query used when broadcasting calendar snapshots.
    case snapshots(CalendarAgentQuery)
    /// Filter used when streaming live process logs.
    case logs(IPC.LogSubscription)
  }

  /// Disposition returned after handling one client request.
  private typealias ClientDisposition = LineSocketServerTransport<
    Subscriber,
    CalendarAgentRequest,
    CalendarAgentMessage
  >.ClientDisposition

  /// Snapshot provider used to answer requests.
  private var provider: CalendarSnapshotProvider?
  /// EasyBar app version reported to clients.
  private let appVersion: String
  /// Logger used for socket-server diagnostics.
  private let logger: ProcessLogger
  /// Host callback invoked after a restart acknowledgement has been sent.
  private let onRestartRequested: @MainActor () -> Void
  /// Line-delimited socket transport backing the server.
  private let transport: LineSocketServerTransport<Subscriber, CalendarAgentRequest, CalendarAgentMessage>

  /// Builds the calendar socket server for one socket path.
  init(
    socketPath: String,
    appVersion: String,
    logger: ProcessLogger,
    onRestartRequested: @escaping @MainActor () -> Void
  ) {
    self.appVersion = appVersion
    self.logger = logger
    self.onRestartRequested = onRestartRequested
    transport = LineSocketServerTransport(
      socketPath: socketPath,
      serverLabel: "calendar agent",
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
        CalendarAgentMessage(kind: .logRecord, logRecord: event)
      }
    )
  }

  /// Starts accepting calendar agent requests.
  @discardableResult
  func start(provider: CalendarSnapshotProvider) -> Bool {
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

  /// Stops the calendar socket server.
  func stop() {
    transport.stop()
    provider = nil
  }

  /// Broadcasts fresh snapshots to all subscribers.
  func broadcastSnapshots() {
    guard let provider else { return }

    for entry in transport.subscribersSnapshot() {
      guard case .snapshots(let query) = entry.subscriber else { continue }
      _ = transport.enqueue(
        CalendarAgentMessage(
          kind: .snapshot,
          snapshot: provider.snapshot(for: query)
        ),
        to: entry.fd
      )
    }
  }

  /// Handles one calendar agent client request.
  private func handleClient(
    _ clientFD: Int32,
    request: CalendarAgentRequest
  ) -> ClientDisposition {
    logger.debug(
      "calendar agent request",
      .field("fd", clientFD),
      .field("command", request.command.rawValue),
    )

    do {
      try CalendarAgentRequestValidator.validate(request)
    } catch {
      logger.warn(
        "calendar agent request rejected",
        .field("command", request.command.rawValue),
        .field("error", error)
      )
      return sendError(
        to: clientFD,
        requestID: request.requestID,
        code: .invalidRequest,
        message: errorMessage(for: error, code: .invalidRequest)
      )
    }

    switch request.command {
    case .version:
      return sendVersion(to: clientFD, requestID: request.requestID)
    case .ping:
      return sendPong(to: clientFD, requestID: request.requestID)
    case .fetch:
      return handleFetch(to: clientFD, request: request)
    case .subscribe:
      return handleSubscribe(to: clientFD, request: request)
    case .logs:
      return handleLogs(to: clientFD, request: request)
    case .restart:
      return handleRestart(to: clientFD, requestID: request.requestID)
    case .createEvent:
      return handleCreateEvent(to: clientFD, request: request)
    case .updateEvent:
      return handleUpdateEvent(to: clientFD, request: request)
    case .deleteEvent:
      return handleDeleteEvent(to: clientFD, request: request)
    }
  }

  /// Acknowledges the request before allowing the host app to terminate.
  private func handleRestart(to clientFD: Int32, requestID: String?) -> ClientDisposition {
    return transport.closeAfterSending(
      CalendarAgentMessage(kind: .restarting, requestID: requestID),
      to: clientFD
    ) {
      [onRestartRequested] in
      onRestartRequested()
    }
  }

  /// Sends the calendar-agent version response.
  private func sendVersion(to clientFD: Int32, requestID: String?) -> ClientDisposition {
    transport.closeAfterSending(
      CalendarAgentMessage(
        kind: .version,
        requestID: requestID,
        version: CalendarAgentVersion(
          appVersion: appVersion,
          protocolVersion: easyBarIPCProtocolVersion
        )
      ),
      to: clientFD
    )
  }

  /// Sends a pong response.
  private func sendPong(to clientFD: Int32, requestID: String?) -> ClientDisposition {
    return transport.closeAfterSending(
      CalendarAgentMessage(kind: .pong, requestID: requestID),
      to: clientFD
    )
  }

  /// Handles a one-shot snapshot fetch.
  private func handleFetch(
    to clientFD: Int32,
    request: CalendarAgentRequest
  ) -> ClientDisposition {
    guard let provider, let query = request.query else {
      return sendError(
        to: clientFD,
        requestID: request.requestID,
        code: .missingQuery,
        message: "Missing calendar query."
      )
    }

    let snapshot = provider.snapshot(for: query)
    return transport.closeAfterSending(
      CalendarAgentMessage(
        kind: .snapshot,
        requestID: request.requestID,
        snapshot: snapshot
      ),
      to: clientFD
    )
  }

  /// Handles a live snapshot subscription.
  private func handleSubscribe(
    to clientFD: Int32,
    request: CalendarAgentRequest
  ) -> ClientDisposition {
    guard let provider, let query = request.query else {
      return sendError(
        to: clientFD,
        requestID: request.requestID,
        code: .missingQuery,
        message: "Missing calendar query."
      )
    }

    guard transport.addSubscriber(.snapshots(query), for: clientFD) else {
      logger.warn("calendar agent subscriber rejected", .field("fd", clientFD))
      return .close
    }
    logger.info(
      "calendar agent subscriber registered",
      .field("fd", clientFD),
    )

    guard
      transport.send(
        CalendarAgentMessage(kind: .subscribed, requestID: request.requestID), to: clientFD)
    else {
      _ = transport.removeSubscriber(fd: clientFD)
      return .close
    }

    let snapshot = provider.snapshot(for: query)
    guard
      transport.send(
        CalendarAgentMessage(
          kind: .snapshot,
          requestID: request.requestID,
          snapshot: snapshot
        ),
        to: clientFD
      )
    else {
      _ = transport.removeSubscriber(fd: clientFD)
      return .close
    }

    return .keepOpen
  }

  /// Handles one bounded live-log subscription.
  private func handleLogs(
    to clientFD: Int32,
    request: CalendarAgentRequest
  ) -> ClientDisposition {
    guard let subscription = request.logSubscription else {
      return sendError(
        to: clientFD,
        requestID: request.requestID,
        code: .invalidRequest,
        message: "Missing live log subscription."
      )
    }

    guard transport.addSubscriber(.logs(subscription), for: clientFD) else {
      return .close
    }
    guard
      transport.send(
        CalendarAgentMessage(
          kind: .logSubscribed,
          requestID: request.requestID
        ),
        to: clientFD
      )
    else {
      _ = transport.removeSubscriber(fd: clientFD)
      return .close
    }
    return .keepOpen
  }

  /// Handles event creation.
  private func handleCreateEvent(
    to clientFD: Int32,
    request: CalendarAgentRequest
  ) -> ClientDisposition {
    guard let createEvent = request.createEvent else {
      return sendError(
        to: clientFD,
        requestID: request.requestID,
        code: .missingCreateEvent,
        message: "Missing create-event payload."
      )
    }

    return handleMutation(
      to: clientFD,
      requestID: request.requestID,
      successKind: .created,
      failureLogMessage: "calendar event creation failed"
    ) { provider in
      _ = try provider.createEvent(createEvent)
    }
  }

  /// Handles event updates.
  private func handleUpdateEvent(
    to clientFD: Int32,
    request: CalendarAgentRequest
  ) -> ClientDisposition {
    guard let updateEvent = request.updateEvent else {
      return sendError(
        to: clientFD,
        requestID: request.requestID,
        code: .missingUpdateEvent,
        message: "Missing update-event payload."
      )
    }

    return handleMutation(
      to: clientFD,
      requestID: request.requestID,
      successKind: .updated,
      failureLogMessage: "calendar event update failed"
    ) { provider in
      try provider.updateEvent(updateEvent)
    }
  }

  /// Handles event deletion.
  private func handleDeleteEvent(
    to clientFD: Int32,
    request: CalendarAgentRequest
  ) -> ClientDisposition {
    guard let deleteEvent = request.deleteEvent else {
      return sendError(
        to: clientFD,
        requestID: request.requestID,
        code: .missingDeleteEvent,
        message: "Missing delete-event payload."
      )
    }

    return handleMutation(
      to: clientFD,
      requestID: request.requestID,
      successKind: .deleted,
      failureLogMessage: "calendar event delete failed"
    ) { provider in
      try provider.deleteEvent(deleteEvent)
    }
  }

  /// Runs one calendar mutation and sends either its success kind or a structured error.
  private func handleMutation(
    to clientFD: Int32,
    requestID: String?,
    successKind: CalendarAgentMessageKind,
    failureLogMessage: String,
    action: (CalendarSnapshotProvider) throws -> Void
  ) -> ClientDisposition {
    guard let provider else {
      return sendError(
        to: clientFD,
        requestID: requestID,
        code: .unknown,
        message: "Calendar provider is unavailable."
      )
    }

    do {
      try action(provider)
      _ = transport.send(
        CalendarAgentMessage(kind: successKind, requestID: requestID), to: clientFD)
    } catch {
      sendMutationError(
        error,
        to: clientFD,
        requestID: requestID,
        logMessage: failureLogMessage
      )
    }

    return .close
  }

  /// Sends a structured error response.
  private func sendError(
    to clientFD: Int32,
    requestID: String?,
    code: CalendarAgentErrorCode,
    message: String
  ) -> ClientDisposition {
    _ = transport.send(
      CalendarAgentMessage(
        kind: .error,
        requestID: requestID,
        errorCode: code,
        message: message
      ),
      to: clientFD
    )
    return .close
  }

  /// Logs and sends one calendar mutation failure.
  private func sendMutationError(
    _ error: Error,
    to clientFD: Int32,
    requestID: String?,
    logMessage: String
  ) {
    let code = errorCode(for: error, fallback: .unknown)
    logger.error(
      logMessage,
      .field("error", error),
      .field("code", code.rawValue),
    )
    _ = transport.send(
      CalendarAgentMessage(
        kind: .error,
        requestID: requestID,
        errorCode: code,
        message: errorMessage(for: error, code: code)
      ),
      to: clientFD
    )
  }

  /// Maps one calendar-domain error to a stable wire-level error code.
  private func errorCode(
    for error: Error,
    fallback: CalendarAgentErrorCode
  ) -> CalendarAgentErrorCode {
    if let createError = error as? CalendarAgentCreateError {
      switch createError {
      case .accessDenied:
        return .accessDenied
      case .invalidDateRange:
        return .invalidDateRange
      case .noWritableCalendar:
        return .noWritableCalendar
      case .eventIdentifierUnavailable:
        return .eventIdentifierUnavailable
      }
    }

    if let mutationError = error as? CalendarAgentMutationError {
      switch mutationError {
      case .eventNotFound:
        return .eventNotFound
      }
    }

    return fallback
  }

  /// Builds one readable wire-level error message from a calendar-domain error.
  private func errorMessage(for error: Error, code: CalendarAgentErrorCode) -> String {
    if let localizedError = error as? LocalizedError,
      let description = localizedError.errorDescription,
      !description.isEmpty
    {
      return description
    }

    let nsError = error as NSError
    let description = nsError.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)

    if !description.isEmpty,
      description.caseInsensitiveCompare("The operation couldn’t be completed.") != .orderedSame
    {
      return "\(description) [\(nsError.domain) \(nsError.code)]"
    }

    return "\(code.rawValue) [\(nsError.domain) \(nsError.code)]"
  }
}
