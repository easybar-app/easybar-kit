import Foundation

/// Sends one newline-delimited request to the calendar agent and reads one response.
public enum CalendarAgentOneShotClient {
  private static let makeEncoder: @Sendable () -> JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }

  /// Sends one request and returns the first decoded response.
  public static func send(
    request: CalendarAgentRequest,
    socketPath: String
  ) throws -> CalendarAgentMessage {
    let transport = LineSocketClientTransport<CalendarAgentRequest, CalendarAgentMessage>(
      socketPath: socketPath,
      makeEncoder: makeEncoder
    )

    do {
      return try transport.send(request: request)
    } catch let error as LineSocketClientTransportError {
      throw CalendarAgentOneShotError(transportError: error)
    }
  }
}

/// Errors produced by the one-shot calendar agent client.
public enum CalendarAgentOneShotError: LocalizedError {
  case socketCreationFailed
  case connectionFailed
  case writeFailed
  case readFailed
  case emptyResponse

  /// Creates a calendar agent one shot error.
  init(transportError: LineSocketClientTransportError) {
    switch transportError {
    case .socketFailed:
      self = .socketCreationFailed
    case .connectFailed, .connectionTimedOut:
      self = .connectionFailed
    case .encodeFailed, .writeFailed, .writeTimedOut:
      self = .writeFailed
    case .decodeFailed, .readFailed, .responseTimedOut:
      self = .readFailed
    case .noReply:
      self = .emptyResponse
    }
  }

  /// Returns the localized client error message.
  public var errorDescription: String? {
    switch self {
    case .socketCreationFailed:
      return "Failed to create the calendar agent socket."
    case .connectionFailed:
      return "Failed to connect to the calendar agent."
    case .writeFailed:
      return "Failed to send the request to the calendar agent."
    case .readFailed:
      return "Failed to read the calendar agent response."
    case .emptyResponse:
      return "The calendar agent returned an empty response."
    }
  }
}
