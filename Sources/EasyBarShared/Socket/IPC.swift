import Foundation

/// Shared IPC protocol types used between EasyBar and its clients.
public enum IPC {}

extension IPC {
  /// Commands received through the EasyBar IPC socket.
  public enum Command: String, Codable, Sendable {
    case manualRefresh = "manual_refresh"
    case workspaceChange = "workspace_change"
    case focusChange = "focus_change"
    case spaceModeChange = "space_mode_change"
    case restartLuaRuntime = "restart_lua_runtime"
    case reloadConfig = "reload_config"
    case validateConfig = "validate_config"
    case metrics = "metrics"
    case logs = "logs"
    case inboxSend = "inbox_send"
    case inboxRead = "inbox_read"
    case inboxMarkRead = "inbox_mark_read"
    case inboxMarkUnread = "inbox_mark_unread"
    case inboxDismiss = "inbox_dismiss"
    case inboxRemove = "inbox_remove"
    case inboxClear = "inbox_clear"
  }

  /// Severity accepted by control-socket inbox messages.
  public enum InboxSeverity: String, Codable, CaseIterable, Sendable {
    case info
    case success
    case warning
    case error
  }

  /// One inbox item exchanged through the control socket.
  public struct InboxItem: Codable, Equatable, Sendable {
    /// The source for this inbox item.
    public let source: String
    /// The stable identifier for this inbox item.
    public let id: String
    /// The title for this inbox item.
    public let title: String
    /// The message for this inbox item.
    public let message: String?
    /// The severity for this inbox item.
    public let severity: InboxSeverity
    /// The group for this inbox item.
    public let group: String?
    /// The URL for this inbox item.
    public let url: String?
    /// The timestamp for this inbox item.
    public let timestamp: TimeInterval
    /// Whether this inbox item is unread.
    public let unread: Bool

    /// Creates an inbox item.
    public init(
      source: String,
      id: String,
      title: String,
      message: String? = nil,
      severity: InboxSeverity = .info,
      group: String? = nil,
      url: String? = nil,
      timestamp: TimeInterval,
      unread: Bool = true
    ) {
      self.source = source
      self.id = id
      self.title = title
      self.message = message
      self.severity = severity
      self.group = group
      self.url = url
      self.timestamp = timestamp
      self.unread = unread
    }
  }

  /// Mutation or query sent to the native inbox.
  public struct InboxRequest: Codable, Equatable, Sendable {
    /// Defines the supported operation values.
    public enum Operation: String, Codable, Sendable {
      case send
      case read
      case markRead = "mark_read"
      case markUnread = "mark_unread"
      case dismiss
      case remove
      case clear
    }

    /// The operation for this inbox request.
    public let operation: Operation
    /// The item for this inbox request.
    public let item: InboxItem?
    /// The source for this inbox request.
    public let source: String?
    /// The stable identifier for this inbox request.
    public let id: String?
    /// Whether the unread only option is enabled for this inbox request.
    public let unreadOnly: Bool

    /// Maps stored properties to their encoded keys.
    private enum CodingKeys: String, CodingKey {
      case operation
      case item
      case source
      case id
      case unreadOnly = "unread_only"
    }

    /// Creates an inbox request.
    public init(
      operation: Operation,
      item: InboxItem? = nil,
      source: String? = nil,
      id: String? = nil,
      unreadOnly: Bool = false
    ) {
      self.operation = operation
      self.item = item
      self.source = source
      self.id = id
      self.unreadOnly = unreadOnly
    }
  }

  /// One IPC request sent to the EasyBar socket.
  public enum Request: Codable, Sendable {
    case command(Command)
    case validateConfig(configPath: String?)
    case metrics(watch: Bool)
    case logs(LogSubscription)
    case inbox(InboxRequest)

    /// Maps stored properties to their encoded keys.
    private enum CodingKeys: String, CodingKey {
      case command
      case configPath = "config_path"
      case watch
      case logs
      case inbox
    }

    /// Builds one non-streaming IPC command request.
    public static func makeCommand(_ command: Command) -> Self {
      switch command {
      case .metrics:
        return .metrics(watch: false)
      case .logs:
        return .logs(LogSubscription())
      case .validateConfig:
        return .validateConfig(configPath: nil)
      case .inboxSend, .inboxRead, .inboxMarkRead, .inboxMarkUnread, .inboxDismiss, .inboxRemove,
        .inboxClear:
        preconditionFailure("inbox commands require an inbox request payload")
      default:
        return .command(command)
      }
    }

    /// Builds one config validation request.
    public static func makeValidateConfig(configPath: String? = nil) -> Self {
      return .validateConfig(configPath: configPath)
    }

    /// Builds one metrics request.
    public static func makeMetrics(watch: Bool = false) -> Self {
      return .metrics(watch: watch)
    }

    /// Builds one live log request.
    public static func makeLogs(_ subscription: LogSubscription) -> Self {
      return .logs(subscription)
    }

    /// Builds one inbox request.
    public static func makeInbox(_ request: InboxRequest) -> Self {
      return .inbox(request)
    }

    /// Returns the command represented by this request.
    public var command: Command {
      switch self {
      case .command(let command):
        return command
      case .validateConfig:
        return .validateConfig
      case .metrics:
        return .metrics
      case .logs:
        return .logs
      case .inbox(let request):
        switch request.operation {
        case .send: return .inboxSend
        case .read: return .inboxRead
        case .markRead: return .inboxMarkRead
        case .markUnread: return .inboxMarkUnread
        case .dismiss: return .inboxDismiss
        case .remove: return .inboxRemove
        case .clear: return .inboxClear
        }
      }
    }

    /// Returns the config path requested for validation, when present.
    public var configPath: String? {
      switch self {
      case .validateConfig(let configPath):
        return configPath
      case .command, .metrics, .logs, .inbox:
        return nil
      }
    }

    /// Returns whether this request keeps the metrics stream open.
    public var watch: Bool {
      switch self {
      case .command, .validateConfig, .logs, .inbox:
        return false
      case .metrics(let watch):
        return watch
      }
    }

    /// Decodes one IPC request.
    public init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      let command = try container.decode(Command.self, forKey: .command)

      switch command {
      case .metrics:
        self = .metrics(watch: try container.decodeIfPresent(Bool.self, forKey: .watch) ?? false)
      case .logs:
        self = .logs(
          try container.decodeIfPresent(LogSubscription.self, forKey: .logs)
            ?? LogSubscription()
        )
      case .validateConfig:
        self = .validateConfig(
          configPath: try container.decodeIfPresent(String.self, forKey: .configPath)
        )
      default:
        if Self.inboxCommands.contains(command) {
          let request = try container.decode(InboxRequest.self, forKey: .inbox)
          self = .inbox(request)
          guard self.command == command else {
            throw DecodingError.dataCorruptedError(
              forKey: .command,
              in: container,
              debugDescription: "inbox command does not match its operation"
            )
          }
        } else {
          self = .command(command)
        }
      }
    }

    /// Encodes one IPC request.
    public func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)

      switch self {
      case .command(let command):
        try container.encode(command, forKey: .command)

      case .validateConfig(let configPath):
        try container.encode(Command.validateConfig, forKey: .command)
        try container.encodeIfPresent(configPath, forKey: .configPath)

      case .metrics(let watch):
        try container.encode(Command.metrics, forKey: .command)
        if watch {
          try container.encode(watch, forKey: .watch)
        }

      case .logs(let subscription):
        try container.encode(Command.logs, forKey: .command)
        try container.encode(subscription, forKey: .logs)

      case .inbox(let request):
        try container.encode(command, forKey: .command)
        try container.encode(request, forKey: .inbox)
      }
    }

    private static let inboxCommands: Set<Command> = [
      .inboxSend, .inboxRead, .inboxMarkRead, .inboxMarkUnread, .inboxDismiss, .inboxRemove,
      .inboxClear,
    ]
  }

  /// One IPC message returned by the EasyBar socket.
  public enum Message: Codable, Sendable {
    /// Defines the supported kind values.
    public enum Kind: String, Codable, Sendable {
      case accepted
      case rejected
      case configValidated = "config_validated"
      case metrics
      case logSubscribed = "log_subscribed"
      case logRecord = "log_record"
      case inbox
    }

    case accepted
    case rejected(message: String?)
    case configValidated(configPath: String, warnings: [String])
    case metrics(MetricsSnapshot)
    case logSubscribed
    case logRecord(ProcessLogEvent)
    case inbox([InboxItem])

    /// Maps stored properties to their encoded keys.
    private enum CodingKeys: String, CodingKey {
      case kind
      case message
      case configPath = "config_path"
      case metrics
      case warnings
      case log
      case inbox
    }

    /// Returns the message kind for logging and response handling.
    public var kind: Kind {
      switch self {
      case .accepted:
        return .accepted
      case .rejected:
        return .rejected
      case .configValidated:
        return .configValidated
      case .metrics:
        return .metrics
      case .logSubscribed:
        return .logSubscribed
      case .logRecord:
        return .logRecord
      case .inbox:
        return .inbox
      }
    }

    /// Returns the rejection message when present.
    public var message: String? {
      switch self {
      case .rejected(let message):
        return message
      case .accepted, .configValidated, .metrics, .logSubscribed, .logRecord, .inbox:
        return nil
      }
    }

    /// Returns the validated config path when present.
    public var configPath: String? {
      switch self {
      case .configValidated(let configPath, _):
        return configPath
      case .accepted, .rejected, .metrics, .logSubscribed, .logRecord, .inbox:
        return nil
      }
    }

    /// Returns validation warnings when present.
    public var warnings: [String] {
      switch self {
      case .configValidated(_, let warnings):
        return warnings
      case .accepted, .rejected, .metrics, .logSubscribed, .logRecord, .inbox:
        return []
      }
    }

    /// Returns the metrics payload when present.
    public var metrics: MetricsSnapshot? {
      switch self {
      case .metrics(let snapshot):
        return snapshot
      case .accepted, .rejected, .configValidated, .logSubscribed, .logRecord, .inbox:
        return nil
      }
    }

    /// Returns the streamed log event when present.
    public var logEvent: ProcessLogEvent? {
      switch self {
      case .logRecord(let event):
        return event
      case .accepted, .rejected, .configValidated, .metrics, .logSubscribed, .inbox:
        return nil
      }
    }

    /// Decodes one IPC message.
    public init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      let kind = try container.decode(Kind.self, forKey: .kind)

      switch kind {
      case .accepted:
        self = .accepted

      case .rejected:
        self = .rejected(message: try container.decodeIfPresent(String.self, forKey: .message))

      case .configValidated:
        self = .configValidated(
          configPath: try container.decode(String.self, forKey: .configPath),
          warnings: try container.decodeIfPresent([String].self, forKey: .warnings) ?? []
        )

      case .metrics:
        self = .metrics(try container.decode(MetricsSnapshot.self, forKey: .metrics))

      case .logSubscribed:
        self = .logSubscribed

      case .logRecord:
        self = .logRecord(try container.decode(ProcessLogEvent.self, forKey: .log))

      case .inbox:
        self = .inbox(try container.decode([InboxItem].self, forKey: .inbox))
      }
    }

    /// Encodes one IPC message.
    public func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)

      switch self {
      case .accepted:
        try container.encode(Kind.accepted, forKey: .kind)

      case .rejected(let message):
        try container.encode(Kind.rejected, forKey: .kind)
        try container.encodeIfPresent(message, forKey: .message)

      case .configValidated(let configPath, let warnings):
        try container.encode(Kind.configValidated, forKey: .kind)
        try container.encode(configPath, forKey: .configPath)
        if !warnings.isEmpty {
          try container.encode(warnings, forKey: .warnings)
        }

      case .metrics(let snapshot):
        try container.encode(Kind.metrics, forKey: .kind)
        try container.encode(snapshot, forKey: .metrics)

      case .logSubscribed:
        try container.encode(Kind.logSubscribed, forKey: .kind)

      case .logRecord(let event):
        try container.encode(Kind.logRecord, forKey: .kind)
        try container.encode(event, forKey: .log)

      case .inbox(let items):
        try container.encode(Kind.inbox, forKey: .kind)
        try container.encode(items, forKey: .inbox)
      }
    }
  }
}
