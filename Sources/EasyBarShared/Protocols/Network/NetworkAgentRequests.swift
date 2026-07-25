import Foundation

/// One request sent to the network agent.
public struct NetworkAgentRequest: Codable, Sendable {
  /// Command to execute on the agent.
  public var command: NetworkAgentCommand
  /// Requested field keys for fetch and subscribe.
  public var fields: [NetworkAgentField]?
  /// Optional live-log subscription used by the logs command.
  public var logSubscription: IPC.LogSubscription?

  /// Creates one network agent request.
  public init(
    command: NetworkAgentCommand,
    fields: [NetworkAgentField]? = nil,
    logSubscription: IPC.LogSubscription? = nil
  ) {
    self.command = command
    self.fields = fields
    self.logSubscription = logSubscription
  }

  /// Builds one fetch request.
  public static func fetch(_ fields: [NetworkAgentField]) -> Self {
    return Self(command: .fetch, fields: fields)
  }

  /// Builds one subscribe request.
  public static func subscribe(_ fields: [NetworkAgentField]) -> Self {
    return Self(command: .subscribe, fields: fields)
  }

  /// Builds one live-log subscription request.
  public static func logs(_ subscription: IPC.LogSubscription = IPC.LogSubscription()) -> Self {
    return Self(command: .logs, logSubscription: subscription)
  }
}

/// One version payload returned by the network agent.
