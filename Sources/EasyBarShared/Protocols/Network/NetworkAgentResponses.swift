import Foundation

public enum NetworkAgentMessageKind: String, Codable, Sendable {
  case pong
  case version
  case subscribed
  case logSubscribed = "log_subscribed"
  case logRecord = "log_record"
  case restarting
  case fields
  case error
}

/// Availability of one requested network-agent field.
public enum NetworkAgentFieldStatus: String, Codable, Equatable, Sendable {
  /// The field was resolved and is present in the values payload.
  case available
  /// The field was intentionally withheld because location authorization is unavailable.
  case permissionDenied = "permission_denied"
  /// The field is supported but no value is currently available.
  case unavailable
}

/// One message sent over the network agent socket.
public struct NetworkAgentMessage: Codable, Sendable {
  /// Message kind discriminator.
  public var kind: NetworkAgentMessageKind
  /// Optional version payload.
  public var version: NetworkAgentVersion?
  /// Optional field values payload.
  public var fields: [String: NetworkAgentFieldValue]?
  /// Availability metadata for every requested field.
  public var fieldStatuses: [String: NetworkAgentFieldStatus]?
  /// Optional stable wire-level error code.
  public var errorCode: NetworkAgentErrorCode?
  /// Optional human-readable error message.
  public var message: String?
  /// Optional live log record payload.
  public var logRecord: ProcessLogEvent?

  /// Creates one network agent message.
  public init(
    kind: NetworkAgentMessageKind,
    version: NetworkAgentVersion? = nil,
    fields: [String: NetworkAgentFieldValue]? = nil,
    fieldStatuses: [String: NetworkAgentFieldStatus]? = nil,
    errorCode: NetworkAgentErrorCode? = nil,
    message: String? = nil,
    logRecord: ProcessLogEvent? = nil
  ) {
    self.kind = kind
    self.version = version
    self.fields = fields
    self.fieldStatuses = fieldStatuses
    self.errorCode = errorCode
    self.message = message
    self.logRecord = logRecord
  }
}
