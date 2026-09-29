import Foundation

/// Scalar or string-array value accepted by widget-backed TOML storage.
enum WidgetStorageValue: Codable, Equatable, Sendable {
  case string(String)
  case integer(Int)
  case double(Double)
  case bool(Bool)
  case stringArray([String])

  /// Creates a widget storage value.
  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Int.self) {
      self = .integer(value)
    } else if let value = try? container.decode(Double.self) {
      self = .double(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([String].self) {
      self = .stringArray(value)
    } else {
      throw DecodingError.typeMismatch(
        WidgetStorageValue.self,
        .init(
          codingPath: decoder.codingPath,
          debugDescription: "widget storage values must be strings, booleans, numbers, or string arrays"
        )
      )
    }
  }

  /// Encodes the requested value.
  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .string(let value):
      try container.encode(value)
    case .integer(let value):
      try container.encode(value)
    case .double(let value):
      try container.encode(value)
    case .bool(let value):
      try container.encode(value)
    case .stringArray(let value):
      try container.encode(value)
    }
  }
}

/// Protocol version expected between EasyBar and the Lua widget runtime.
let easyBarLuaRuntimeProtocolVersion = 1

/// Decoded message emitted by the Lua widget runtime.
struct WidgetTreeUpdate: Codable, Sendable {

  /// The protocol version for this widget tree update.
  let protocolVersion: Int?
  /// The type for this widget tree update.
  let type: Kind
  /// The root for this widget tree update.
  let root: String?
  /// The nodes for this widget tree update.
  let nodes: [WidgetNodeState]?
  /// The events for this widget tree update.
  let events: [String]?
  /// The token for this widget tree update.
  let token: String?
  /// The command for this widget tree update.
  let command: String?
  /// The arguments for this widget tree update.
  let arguments: [String]?
  /// Whether the sync option is enabled for this widget tree update.
  let sync: Bool?
  /// The delay seconds for this widget tree update.
  let delaySeconds: TimeInterval?
  /// The timeout seconds for this widget tree update.
  let timeoutSeconds: TimeInterval?
  /// The max output bytes for this widget tree update.
  let maxOutputBytes: Int?
  /// The widget for this widget tree update.
  let widget: String?
  /// The operation for this widget tree update.
  let operation: String?
  /// The source for this widget tree update.
  let source: String?
  /// The items for this widget tree update.
  let items: [InboxItem]?
  /// The actions for this widget tree update.
  let actions: [InboxAction]?
  /// The order for this widget tree update.
  let order: Int?
  /// The presentation for this widget tree update.
  let presentation: InboxSourcePresentation?
  /// The key for this widget tree update.
  let key: String?
  /// The value for this widget tree update.
  let value: WidgetStorageValue?

  /// Maps stored properties to their encoded keys.
  enum CodingKeys: String, CodingKey {
    case protocolVersion
    case type
    case root
    case nodes
    case events
    case token
    case command
    case arguments
    case sync
    case delaySeconds
    case timeoutSeconds
    case maxOutputBytes
    case widget
    case operation
    case source
    case items
    case actions
    case order
    case presentation
    case key
    case value
  }

  /// Defines the supported kind values.
  enum Kind: String, Codable, Sendable {
    case subscriptions
    case ready
    case tree
    case clearRoot = "clear_root"
    case commandRequest = "command_request"
    case commandCancel = "command_cancel"
    case timerRequest = "timer_request"
    case timerCancel = "timer_cancel"
    case inboxReplace = "inbox_replace"
    case inboxClear = "inbox_clear"
    case inboxConfigure = "inbox_configure"
    case storageRequest = "storage_request"
  }

  /// Returns whether this update contains subscriptions.
  var isSubscriptions: Bool {
    return type == .subscriptions
  }

  /// Returns whether this update uses the expected host/runtime protocol version.
  var isSupportedProtocolVersion: Bool {
    return protocolVersion == easyBarLuaRuntimeProtocolVersion
  }

  /// Returns whether this update is the runtime ready signal.
  var isReady: Bool {
    return type == .ready
  }

  /// Returns whether this update contains a widget tree.
  var isTree: Bool {
    return type == .tree
  }

  /// Returns whether this update explicitly clears one rendered root.
  var isClearRoot: Bool {
    return type == .clearRoot
  }

  /// Returns whether this update is a host command execution request.
  var isCommandRequest: Bool {
    return type == .commandRequest
  }

  /// Returns the asynchronous command token to cancel when present.
  var commandCancelToken: String? {
    guard type == .commandCancel else { return nil }
    return token
  }

  /// Returns the timer token to cancel when present.
  var timerCancelToken: String? {
    guard type == .timerCancel else { return nil }
    return token
  }

  /// Returns the timer request payload when present.
  var timerRequestPayload: (token: String, delaySeconds: TimeInterval)? {
    guard type == .timerRequest, let token, let delaySeconds else { return nil }
    return (token: token, delaySeconds: delaySeconds)
  }

  /// The inbox replace payload for this widget tree update.
  var inboxReplacePayload: InboxSourceSnapshot? {
    guard type == .inboxReplace, let source, let items else { return nil }
    return InboxSourceSnapshot(source: source, items: items)
  }

  /// The inbox clear source for this widget tree update.
  var inboxClearSource: String? {
    guard type == .inboxClear else { return nil }
    return source
  }

  /// The inbox configuration payload for this widget tree update.
  var inboxConfigurationPayload: InboxSourceConfiguration? {
    guard type == .inboxConfigure, let source, let actions else { return nil }
    return InboxSourceConfiguration(
      source: source,
      actions: actions,
      order: order,
      presentation: presentation
    )
  }

  /// The storage request payload for this widget tree update.
  var storageRequestPayload:
    (token: String, widget: String, key: String, operation: String, value: WidgetStorageValue?)?
  {
    guard type == .storageRequest, let token, let widget, let key, let operation else { return nil }
    return (token: token, widget: widget, key: key, operation: operation, value: value)
  }

  /// Returns the subscribed event names or an empty list.
  var subscribedEvents: [String] {
    return events ?? []
  }

  /// Returns whether this update includes a decoded tree payload.
  var hasTreePayload: Bool {
    return root != nil && nodes != nil
  }

  /// Returns the decoded tree payload when present.
  var treePayload: (root: String, nodes: [WidgetNodeState])? {
    guard let root, let nodes else { return nil }
    return (root: root, nodes: nodes)
  }

  /// Returns the root identifier to clear when present.
  var clearRootID: String? {
    guard isClearRoot else { return nil }
    return root
  }

  /// Returns the decoded command request payload when present.
  var commandRequestPayload:
    (
      token: String,
      command: String,
      arguments: [String]?,
      invocation: LuaCommandInvocation,
      isSynchronous: Bool,
      timeoutSeconds: TimeInterval?,
      maxOutputBytes: Int?,
      widget: String?,
      operation: String?
    )?
  {
    guard let token, let sync else { return nil }

    let invocation: LuaCommandInvocation
    if let command, !command.isEmpty, arguments == nil {
      invocation = .shell(command)
    } else if command == nil, let arguments, !arguments.isEmpty {
      invocation = .executable(arguments)
    } else {
      return nil
    }

    let displayCommand: String
    let directArguments: [String]?
    switch invocation {
    case .shell(let command):
      displayCommand = command
      directArguments = nil
    case .executable(let arguments):
      displayCommand = arguments.joined(separator: " ")
      directArguments = arguments
    }

    return (
      token: token,
      command: displayCommand,
      arguments: directArguments,
      invocation: invocation,
      isSynchronous: sync,
      timeoutSeconds: timeoutSeconds,
      maxOutputBytes: maxOutputBytes,
      widget: widget,
      operation: operation
    )
  }
}
