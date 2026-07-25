import Darwin
import EasyBarShared
import Foundation

/// One process socket that can supply live EasyBar log records.
enum LogStreamEndpoint: Equatable, Sendable {
  case easyBar(path: String)
  case calendarAgent(path: String)
  case networkAgent(path: String)

  var path: String {
    switch self {
    case .easyBar(let path), .calendarAgent(let path), .networkAgent(let path):
      return path
    }
  }

  var label: String {
    switch self {
    case .easyBar:
      return "EasyBar"
    case .calendarAgent:
      return "calendar agent"
    case .networkAgent:
      return "network agent"
    }
  }
}

/// Errors produced while following live logs from one or more processes.
enum LogStreamClientError: LocalizedError {
  case connectionFailed(endpoint: String, message: String)
  case rejected(endpoint: String, message: String)
  case unexpectedMessage(endpoint: String, kind: String)
  case streamClosed(endpoint: String)
  case pollFailed(String)
  case readFailed(endpoint: String, message: String)
  case writeFailed(endpoint: String, message: String)

  var errorDescription: String? {
    switch self {
    case .connectionFailed(let endpoint, let message):
      return "failed to connect to the \(endpoint) log stream: \(message)"
    case .rejected(let endpoint, let message):
      return "\(endpoint) rejected the log stream: \(message)"
    case .unexpectedMessage(let endpoint, let kind):
      return "unexpected \(endpoint) log stream message: \(kind)"
    case .streamClosed(let endpoint):
      return "\(endpoint) closed the live log stream"
    case .pollFailed(let message):
      return "live log stream polling failed: \(message)"
    case .readFailed(let endpoint, let message):
      return "failed reading the \(endpoint) log stream: \(message)"
    case .writeFailed(let endpoint, let message):
      return "failed subscribing to the \(endpoint) log stream: \(message)"
    }
  }
}

/// Multiplexes bounded live log streams from EasyBar and its enabled agents.
struct LogStreamClient {
  let endpoints: [LogStreamEndpoint]

  /// Connects every requested process before exposing retained history or live records.
  func stream(
    subscription: IPC.LogSubscription,
    onSubscribed: () throws -> Void,
    onRecord: (ProcessLogRecord) throws -> Void
  ) throws {
    guard !endpoints.isEmpty else {
      throw AppError.message("no running EasyBar process was selected for live logs")
    }

    var connections: [Connection] = []
    do {
      for endpoint in endpoints {
        connections.append(try openConnection(to: endpoint, subscription: subscription))
      }
    } catch {
      for connection in connections {
        close(connection.fd)
      }
      throw error
    }
    defer {
      for connection in connections {
        close(connection.fd)
      }
    }

    var bufferedRecords: [ProcessLogRecord] = []
    while connections.contains(where: { !$0.subscribed }) {
      for (index, signal) in try pollConnections(&connections) {
        switch signal {
        case .subscribed:
          connections[index].subscribed = true
        case .record(let record):
          bufferedRecords.append(record)
        case .rejected(let message):
          throw LogStreamClientError.rejected(
            endpoint: connections[index].endpoint.label,
            message: message
          )
        case .unexpected(let kind):
          throw LogStreamClientError.unexpectedMessage(
            endpoint: connections[index].endpoint.label,
            kind: kind
          )
        }
      }
    }

    try onSubscribed()
    for record in bufferedRecords {
      try onRecord(record)
    }

    while true {
      for (index, signal) in try pollConnections(&connections) {
        switch signal {
        case .record(let record):
          try onRecord(record)
        case .subscribed:
          throw LogStreamClientError.unexpectedMessage(
            endpoint: connections[index].endpoint.label,
            kind: "duplicate log_subscribed"
          )
        case .rejected(let message):
          throw LogStreamClientError.rejected(
            endpoint: connections[index].endpoint.label,
            message: message
          )
        case .unexpected(let kind):
          throw LogStreamClientError.unexpectedMessage(
            endpoint: connections[index].endpoint.label,
            kind: kind
          )
        }
      }
    }
  }

  private func openConnection(
    to endpoint: LogStreamEndpoint,
    subscription: IPC.LogSubscription
  ) throws -> Connection {
    let fd: Int32
    do {
      fd = try openConnectedUnixSocket(at: endpoint.path)
    } catch {
      throw LogStreamClientError.connectionFailed(
        endpoint: endpoint.label,
        message: error.localizedDescription
      )
    }

    do {
      try sendSubscription(subscription, endpoint: endpoint, to: fd)
    } catch {
      close(fd)
      throw error
    }

    return Connection(
      endpoint: endpoint,
      fd: fd,
      decoder: DecoderState(endpoint: endpoint)
    )
  }

  private func sendSubscription(
    _ subscription: IPC.LogSubscription,
    endpoint: LogStreamEndpoint,
    to fd: Int32
  ) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]

    let payload: Data
    do {
      switch endpoint {
      case .easyBar:
        payload = try encoder.encode(IPC.Request.makeLogs(subscription))
      case .calendarAgent:
        payload = try encoder.encode(CalendarAgentRequest.logs(subscription))
      case .networkAgent:
        payload = try encoder.encode(NetworkAgentRequest.logs(subscription))
      }
    } catch {
      throw LogStreamClientError.writeFailed(
        endpoint: endpoint.label,
        message: error.localizedDescription
      )
    }

    if let error = writeAll(
      payload + Data([0x0A]),
      to: fd,
      timeout: 1
    ) {
      throw LogStreamClientError.writeFailed(
        endpoint: endpoint.label,
        message: String(describing: error)
      )
    }
  }

  private func pollConnections(
    _ connections: inout [Connection]
  ) throws -> [(Int, Signal)] {
    var descriptors = connections.map {
      pollfd(fd: $0.fd, events: Int16(POLLIN | POLLHUP | POLLERR), revents: 0)
    }

    let result = descriptors.withUnsafeMutableBufferPointer { buffer in
      Darwin.poll(buffer.baseAddress, nfds_t(buffer.count), -1)
    }
    if result < 0 {
      if errno == EINTR { return [] }
      throw LogStreamClientError.pollFailed(String(cString: strerror(errno)))
    }

    var signals: [(Int, Signal)] = []
    for index in descriptors.indices where descriptors[index].revents != 0 {
      let revents = descriptors[index].revents
      if revents & Int16(POLLIN) != 0 {
        signals.append(
          contentsOf: try readAvailable(from: index, connections: &connections)
            .map { (index, $0) }
        )
      } else if revents & Int16(POLLHUP | POLLERR | POLLNVAL) != 0 {
        throw LogStreamClientError.streamClosed(endpoint: connections[index].endpoint.label)
      }
    }
    return signals
  }

  private func readAvailable(
    from index: Int,
    connections: inout [Connection]
  ) throws -> [Signal] {
    var buffer = [UInt8](repeating: 0, count: 4096)
    let count = buffer.withUnsafeMutableBytes { rawBuffer -> Int in
      guard let baseAddress = rawBuffer.baseAddress else { return -1 }
      return Darwin.read(connections[index].fd, baseAddress, rawBuffer.count)
    }

    if count > 0 {
      return try connections[index].decoder.append(buffer.prefix(count))
    }

    if count == 0 {
      let signals = try connections[index].decoder.flush()
      if !signals.isEmpty {
        return signals
      }
      throw LogStreamClientError.streamClosed(endpoint: connections[index].endpoint.label)
    }

    if errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK { return [] }
    throw LogStreamClientError.readFailed(
      endpoint: connections[index].endpoint.label,
      message: String(cString: strerror(errno))
    )
  }
}

extension LogStreamClient {
  fileprivate struct Connection {
    let endpoint: LogStreamEndpoint
    let fd: Int32
    var decoder: DecoderState
    var subscribed = false
  }

  fileprivate enum Signal {
    case subscribed
    case record(ProcessLogRecord)
    case rejected(String)
    case unexpected(String)
  }

  fileprivate enum DecoderState {
    case easyBar(LineDelimitedJSONDecoder<IPC.Message>)
    case calendar(LineDelimitedJSONDecoder<CalendarAgentMessage>)
    case network(LineDelimitedJSONDecoder<NetworkAgentMessage>)

    init(endpoint: LogStreamEndpoint) {
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601

      switch endpoint {
      case .easyBar:
        self = .easyBar(LineDelimitedJSONDecoder(decoder: decoder))
      case .calendarAgent:
        self = .calendar(LineDelimitedJSONDecoder(decoder: decoder))
      case .networkAgent:
        self = .network(LineDelimitedJSONDecoder(decoder: decoder))
      }
    }

    mutating func append(_ bytes: ArraySlice<UInt8>) throws -> [Signal] {
      switch self {
      case .easyBar(var decoder):
        let signals = try decoder.append(bytes).map { try Self.signal(from: $0.get()) }
        self = .easyBar(decoder)
        return signals
      case .calendar(var decoder):
        let signals = try decoder.append(bytes).map { try Self.signal(from: $0.get()) }
        self = .calendar(decoder)
        return signals
      case .network(var decoder):
        let signals = try decoder.append(bytes).map { try Self.signal(from: $0.get()) }
        self = .network(decoder)
        return signals
      }
    }

    mutating func flush() throws -> [Signal] {
      switch self {
      case .easyBar(var decoder):
        let signals = try decoder.flush().map { try Self.signal(from: $0.get()) }
        self = .easyBar(decoder)
        return signals
      case .calendar(var decoder):
        let signals = try decoder.flush().map { try Self.signal(from: $0.get()) }
        self = .calendar(decoder)
        return signals
      case .network(var decoder):
        let signals = try decoder.flush().map { try Self.signal(from: $0.get()) }
        self = .network(decoder)
        return signals
      }
    }

    private static func signal(from message: IPC.Message) throws -> Signal {
      switch message {
      case .logSubscribed:
        return .subscribed
      case .logRecord(let event):
        return .record(event.record)
      case .rejected(let message):
        return .rejected(message ?? "live log subscription rejected")
      default:
        return .unexpected(message.kind.rawValue)
      }
    }

    private static func signal(from message: CalendarAgentMessage) throws -> Signal {
      switch message.kind {
      case .logSubscribed:
        return .subscribed
      case .logRecord:
        guard let event = message.logRecord else {
          return .unexpected("log_record without payload")
        }
        return .record(event.record)
      case .error:
        return .rejected(message.message ?? message.errorCode?.rawValue ?? "unknown error")
      default:
        return .unexpected(message.kind.rawValue)
      }
    }

    private static func signal(from message: NetworkAgentMessage) throws -> Signal {
      switch message.kind {
      case .logSubscribed:
        return .subscribed
      case .logRecord:
        guard let event = message.logRecord else {
          return .unexpected("log_record without payload")
        }
        return .record(event.record)
      case .error:
        return .rejected(message.message ?? message.errorCode?.rawValue ?? "unknown error")
      default:
        return .unexpected(message.kind.rawValue)
      }
    }
  }
}
