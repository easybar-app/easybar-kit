import Foundation

/// Sends acknowledged restart requests to the supervised EasyBar helper agents.
public enum AgentRestartClient {
  /// Asks the calendar agent to exit so its service supervisor can relaunch it.
  public static func restartCalendarAgent(socketPath: String) throws {
    let response = try CalendarAgentOneShotClient.send(
      request: CalendarAgentRequest(command: .restart),
      socketPath: socketPath
    )
    guard response.kind == .restarting else {
      throw AgentRestartError.unexpectedResponse
    }
  }

  /// Asks the network agent to exit so its service supervisor can relaunch it.
  public static func restartNetworkAgent(socketPath: String) throws {
    let transport = LineSocketClientTransport<NetworkAgentRequest, NetworkAgentMessage>(
      socketPath: socketPath
    )
    let response: NetworkAgentMessage
    do {
      response = try transport.send(request: NetworkAgentRequest(command: .restart))
    } catch let error as LineSocketClientTransportError {
      throw AgentRestartError.transport(error.description)
    }
    guard response.kind == .restarting else {
      throw AgentRestartError.unexpectedResponse
    }
  }
}

/// Defines the supported agent restart error values.
public enum AgentRestartError: LocalizedError {
  case unexpectedResponse
  case transport(String)

  public var errorDescription: String? {
    switch self {
    case .unexpectedResponse:
      return "agent returned an unexpected restart response"
    case .transport(let message):
      return "agent socket request failed: \(message)"
    }
  }
}
