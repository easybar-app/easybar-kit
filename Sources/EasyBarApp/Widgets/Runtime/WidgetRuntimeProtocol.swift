import Foundation

/// Decoded host-side classification of one Lua runtime protocol message.
enum WidgetRuntimeMessage {
  case subscriptions(Set<String>)
  case ready
  case tree(root: String, nodes: [WidgetNodeState])
  case clearRoot(String)
  case commandRequest(
    token: String,
    invocation: LuaCommandInvocation,
    isSynchronous: Bool,
    timeoutSeconds: TimeInterval?,
    maxOutputBytes: Int?,
    widget: String?,
    operation: String?
  )
  case commandCancel(token: String)
  case timerRequest(token: String, delaySeconds: TimeInterval)
  case timerCancel(token: String)
  case inboxReplace(InboxSourceSnapshot)
  case inboxClear(source: String)
  case inboxConfigure(InboxSourceConfiguration)
  case storageRequest(
    token: String,
    widget: String,
    key: String,
    operation: WidgetStorageOperation,
    value: WidgetStorageValue?
  )
}

enum WidgetStorageOperation: String, Sendable {
  case get
  case set
}

/// Decodes and classifies structured messages emitted by the Lua widget runtime.
struct WidgetRuntimeProtocolDecoder {
  /// Maximum UTF-8 size accepted for opaque command and timer tokens.
  static let maximumTokenBytes = 256

  private let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return decoder
  }()

  /// Decodes one raw protocol line into a typed runtime message.
  func decodeMessage(from line: String) throws -> WidgetRuntimeMessage {
    let update = try decodeUpdate(from: line)

    guard update.isSupportedProtocolVersion else {
      throw WidgetRuntimeProtocolError.unsupportedProtocolVersion(update.protocolVersion)
    }

    switch update.type {
    case .subscriptions:
      return .subscriptions(Set(update.subscribedEvents))
    case .ready:
      return .ready
    case .tree:
      guard let tree = update.treePayload else {
        throw WidgetRuntimeProtocolError.invalidPayload(
          "unknown lua message"
        )
      }
      return .tree(root: tree.root, nodes: tree.nodes)
    case .clearRoot:
      guard let rootID = update.clearRootID else {
        throw WidgetRuntimeProtocolError.invalidPayload(
          "invalid lua clear-root update"
        )
      }
      return .clearRoot(rootID)
    case .commandRequest:
      guard let request = update.commandRequestPayload else {
        throw WidgetRuntimeProtocolError.invalidPayload(
          "invalid lua command request"
        )
      }

      if let timeoutSeconds = request.timeoutSeconds,
        !timeoutSeconds.isFinite || timeoutSeconds <= 0
      {
        throw WidgetRuntimeProtocolError.invalidPayload(
          "invalid lua command timeout override"
        )
      }

      if let maxOutputBytes = request.maxOutputBytes,
        maxOutputBytes <= 0
      {
        throw WidgetRuntimeProtocolError.invalidPayload(
          "invalid lua command output override"
        )
      }

      if case .executable(let arguments) = request.invocation,
        arguments.first?.isEmpty != false || arguments.contains(where: { $0.contains("\0") })
      {
        throw WidgetRuntimeProtocolError.invalidPayload(
          "invalid lua executable arguments"
        )
      }

      let token = try normalizedToken(request.token, name: "command request")
      let widget = try normalizedCommandLogField(request.widget, name: "widget")
      let operation = try normalizedCommandLogField(request.operation, name: "operation")

      return .commandRequest(
        token: token,
        invocation: request.invocation,
        isSynchronous: request.isSynchronous,
        timeoutSeconds: request.timeoutSeconds,
        maxOutputBytes: request.maxOutputBytes,
        widget: widget,
        operation: operation
      )
    case .commandCancel:
      let token = try normalizedToken(update.commandCancelToken, name: "command cancellation")
      return .commandCancel(token: token)
    case .timerRequest:
      guard let request = update.timerRequestPayload,
        request.delaySeconds.isFinite,
        request.delaySeconds >= 0
      else {
        throw WidgetRuntimeProtocolError.invalidPayload(
          "invalid lua timer request"
        )
      }
      let token = try normalizedToken(request.token, name: "timer request")
      return .timerRequest(token: token, delaySeconds: request.delaySeconds)
    case .timerCancel:
      let token = try normalizedToken(update.timerCancelToken, name: "timer cancellation")
      return .timerCancel(token: token)
    case .inboxReplace:
      guard let snapshot = update.inboxReplacePayload,
        !snapshot.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else {
        throw WidgetRuntimeProtocolError.invalidPayload("invalid inbox replacement")
      }
      return .inboxReplace(snapshot)
    case .inboxClear:
      guard let source = update.inboxClearSource,
        !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else {
        throw WidgetRuntimeProtocolError.invalidPayload("invalid inbox clear")
      }
      return .inboxClear(source: source)
    case .inboxConfigure:
      guard let configuration = update.inboxConfigurationPayload,
        !configuration.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else {
        throw WidgetRuntimeProtocolError.invalidPayload("invalid inbox configuration")
      }
      return .inboxConfigure(configuration)
    case .storageRequest:
      guard let request = update.storageRequestPayload,
        let operation = WidgetStorageOperation(rawValue: request.operation)
      else {
        throw WidgetRuntimeProtocolError.invalidPayload("invalid lua storage request")
      }
      let token = try normalizedToken(request.token, name: "storage request")
      let widget = try normalizedStorageSegment(request.widget, name: "widget")
      let key = try normalizedStorageSegment(request.key, name: "key")
      if operation == .get, request.value != nil {
        throw WidgetRuntimeProtocolError.invalidPayload("invalid lua storage get request")
      }
      if operation == .set, request.value == nil {
        throw WidgetRuntimeProtocolError.invalidPayload("invalid lua storage set request")
      }
      if case .double(let value) = request.value, !value.isFinite {
        throw WidgetRuntimeProtocolError.invalidPayload("invalid lua storage number")
      }
      return .storageRequest(
        token: token,
        widget: widget,
        key: key,
        operation: operation,
        value: request.value
      )
    }
  }

  /// Validates one opaque command or timer token without changing its value.
  private func normalizedToken(_ value: String?, name: String) throws -> String {
    guard let value,
      !value.isEmpty,
      value.utf8.count <= Self.maximumTokenBytes,
      !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    else {
      throw WidgetRuntimeProtocolError.invalidPayload(
        "invalid lua \(name) token"
      )
    }
    return value
  }

  /// Validates one optional human-readable command log field.
  private func normalizedCommandLogField(_ value: String?, name: String) throws -> String? {
    guard let value else { return nil }
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty,
      normalized.utf8.count <= 128,
      !normalized.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    else {
      throw WidgetRuntimeProtocolError.invalidPayload(
        "invalid lua command \(name)"
      )
    }
    return normalized
  }

  /// Validates one storage path segment without accepting TOML path syntax.
  private func normalizedStorageSegment(_ value: String, name: String) throws -> String {
    guard !value.isEmpty,
      value.utf8.count <= 128,
      value.unicodeScalars.allSatisfy({
        CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == "-"
      })
    else {
      throw WidgetRuntimeProtocolError.invalidPayload("invalid lua storage \(name)")
    }
    return value
  }

  /// Decodes one structured runtime update line.
  private func decodeUpdate(from line: String) throws -> WidgetTreeUpdate {
    guard let data = line.data(using: .utf8) else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: [], debugDescription: "invalid utf8")
      )
    }

    return try decoder.decode(WidgetTreeUpdate.self, from: data)
  }
}

/// Errors returned while decoding the Lua runtime protocol.
enum WidgetRuntimeProtocolError: Error {
  case unsupportedProtocolVersion(Int?)
  case invalidPayload(String)
}
