import EasyBarShared
import Foundation
import SwiftTOMLEdit

/// Reads and writes widget-owned values below the reserved `[widgets]` config namespace.
actor LuaStorageService {
  private struct Response: Encodable {
    let protocolVersion = easyBarLuaRuntimeProtocolVersion
    let type = "storage_response"
    let token: String
    let ok: Bool
    let found: Bool
    let value: WidgetStorageValue?
    let error: String?

    enum CodingKeys: String, CodingKey {
      case protocolVersion = "protocol_version"
      case type
      case token
      case ok
      case found
      case value
      case error
    }
  }

  private let logger: ProcessLogger
  private let luaRuntime: LuaRuntime
  private let configManager: ConfigManager
  private let encoder = JSONEncoder()

  init(logger: ProcessLogger, luaRuntime: LuaRuntime, configManager: ConfigManager) {
    self.logger = logger
    self.luaRuntime = luaRuntime
    self.configManager = configManager
  }

  func handle(
    token: String,
    widget: String,
    key: String,
    operation: WidgetStorageOperation,
    value: WidgetStorageValue?
  ) async {
    let path = ["widgets", widget, key]

    switch operation {
    case .get:
      await get(token: token, path: path)
    case .set:
      guard let value else {
        await send(token: token, ok: false, found: false, error: "storage value is required")
        return
      }
      await set(token: token, path: path, value: value)
    }
  }

  private func get(token: String, path: [String]) async {
    let configPath = await configManager.configPath()

    do {
      let table = try Self.readConfig(at: configPath)
      guard let stored = Self.value(in: table, at: path) else {
        await send(token: token, ok: true, found: false)
        return
      }
      guard let value = WidgetStorageValue(stored) else {
        await send(
          token: token,
          ok: false,
          found: false,
          error: "stored value has an unsupported TOML type"
        )
        return
      }
      await send(token: token, ok: true, found: true, value: value)
    } catch {
      logger.error("failed to read widget storage", .field("error", error.localizedDescription))
      await send(token: token, ok: false, found: false, error: "could not read config.toml")
    }
  }

  private func set(token: String, path: [String], value: WidgetStorageValue) async {
    let configPath = await configManager.configPath()
    if let table = try? Self.readConfig(at: configPath),
      let existing = Self.value(in: table, at: path).flatMap(WidgetStorageValue.init),
      existing == value
    {
      await send(token: token, ok: true, found: true, value: value)
      return
    }

    let logger = logger
    let edit = TOMLEdit(path: path, value: value.tomlEditValue)
    let didPersist = await MainActor.run {
      ConfigPersistence(configPath: configPath, logger: logger).apply([edit])
    }

    if didPersist {
      await send(token: token, ok: true, found: true, value: value)
    } else {
      await send(token: token, ok: false, found: false, error: "could not update config.toml")
    }
  }

  private func send(
    token: String,
    ok: Bool,
    found: Bool,
    value: WidgetStorageValue? = nil,
    error: String? = nil
  ) async {
    let response = Response(
      token: token,
      ok: ok,
      found: found,
      value: value,
      error: error
    )
    guard let data = try? encoder.encode(response),
      let encoded = String(data: data, encoding: .utf8)
    else {
      logger.error("failed to encode lua storage response")
      return
    }
    await luaRuntime.send(encoded)
  }

  private static func readConfig(at path: String) throws -> TOMLTable {
    let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
    guard FileManager.default.fileExists(atPath: url.path) else {
      return TOMLTable()
    }
    return try TOMLTable(string: String(contentsOf: url, encoding: .utf8))
  }

  private static func value(in table: TOMLTable, at path: [String]) -> TOMLValue? {
    guard let first = path.first else { return nil }
    var current = table[first]
    for segment in path.dropFirst() {
      guard let nested = current?.table else { return nil }
      current = nested[segment]
    }
    return current
  }
}

extension WidgetStorageValue {
  fileprivate init?(_ value: TOMLValue) {
    switch value {
    case .string(let value):
      self = .string(value)
    case .integer(let value):
      self = .integer(value)
    case .double(let value):
      self = .double(value)
    case .bool(let value):
      self = .bool(value)
    case .array(let values):
      let strings = values.compactMap(\.string)
      guard strings.count == values.count else { return nil }
      self = .stringArray(strings)
    case .table, .datetime:
      return nil
    }
  }

  fileprivate var tomlEditValue: TOMLEdit.Value {
    switch self {
    case .string(let value):
      return .string(value)
    case .integer(let value):
      return .integer(value)
    case .double(let value):
      return .double(value)
    case .bool(let value):
      return .bool(value)
    case .stringArray(let value):
      return .stringArray(value)
    }
  }
}
