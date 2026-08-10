import Darwin
import EasyBarShared
import Foundation
import XCTest

@testable import EasyBarKit

class LuaRenderRuntimeTestCase: XCTestCase, @unchecked Sendable {
  let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return decoder
  }()

  var originalConfigSnapshot: ConfigSnapshot!
  var tempDirectoryURL: URL!
  var configFileURL: URL!
  var lockDirectoryURL: URL!
  var loggingDirectoryURL: URL!
  var runtimeDirectoryURL: URL!

  override func setUpWithError() throws {
    try super.setUpWithError()

    originalConfigSnapshot = Config.makeUnloadedConfig().snapshot()
    Config.makeUnloadedConfig().resetToDefaults()

    tempDirectoryURL = try makeTemporaryDirectory()
    configFileURL = tempDirectoryURL.appendingPathComponent("config.toml")
    lockDirectoryURL = tempDirectoryURL.appendingPathComponent("locks", isDirectory: true)
    loggingDirectoryURL = tempDirectoryURL.appendingPathComponent("logs", isDirectory: true)
    runtimeDirectoryURL = tempDirectoryURL.appendingPathComponent("runtime", isDirectory: true)
  }

  override func tearDownWithError() throws {
    Config.makeUnloadedConfig().apply(originalConfigSnapshot)

    if let tempDirectoryURL {
      try? FileManager.default.removeItem(at: tempDirectoryURL)
    }

    try super.tearDownWithError()
  }
}

extension LuaRenderRuntimeTestCase {
  struct RuntimeCommandRequest: Equatable, Sendable {
    let token: String
    let command: String
    let arguments: [String]?
    let isSynchronous: Bool
    let timeoutSeconds: TimeInterval?
    let maxOutputBytes: Int?
    let widget: String?
    let operation: String?
  }

  actor RuntimeHostBridge {
    private struct StorageResponse: Encodable {
      let protocolVersion = easyBarLuaRuntimeProtocolVersion
      let type = "storage_response"
      let token: String
      let ok = true
      let found: Bool
      let value: WidgetStorageValue?

      enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case type
        case token
        case ok
        case found
        case value
      }
    }

    private let recorder: RuntimeUpdateRecorder
    let decoder: JSONDecoder
    private let stdinHandle: FileHandle
    private let asyncResponseDelayNanoseconds: UInt64
    private let autoRespondToCommands: Bool
    private var storageValues: [String: WidgetStorageValue] = [:]

    init(
      recorder: RuntimeUpdateRecorder,
      decoder: JSONDecoder,
      stdinHandle: FileHandle,
      asyncResponseDelayNanoseconds: UInt64,
      autoRespondToCommands: Bool = true
    ) {
      self.recorder = recorder
      self.decoder = decoder
      self.stdinHandle = stdinHandle
      self.asyncResponseDelayNanoseconds = asyncResponseDelayNanoseconds
      self.autoRespondToCommands = autoRespondToCommands
    }

    func handleRuntimeLine(_ line: String) async throws {
      let update = try decoder.decode(WidgetTreeUpdate.self, from: Data(line.utf8))
      await recorder.record(summary: describe(update))

      if let request = update.commandRequestPayload {
        await recorder.append(
          RuntimeCommandRequest(
            token: request.token,
            command: request.command,
            arguments: request.arguments,
            isSynchronous: request.isSynchronous,
            timeoutSeconds: request.timeoutSeconds,
            maxOutputBytes: request.maxOutputBytes,
            widget: request.widget,
            operation: request.operation
          )
        )

        guard autoRespondToCommands else { return }

        if !request.isSynchronous && asyncResponseDelayNanoseconds > 0 {
          try await Task.sleep(nanoseconds: asyncResponseDelayNanoseconds)
        }

        try sendCommandResponse(token: request.token, output: "0", status: 0)
        return
      }

      if let request = update.storageRequestPayload {
        let storageKey = request.widget + ":" + request.key
        if request.operation == "set", let value = request.value {
          storageValues[storageKey] = value
          try sendStorageResponse(token: request.token, found: true, value: value)
        } else {
          let value = storageValues[storageKey]
          try sendStorageResponse(token: request.token, found: value != nil, value: value)
        }
        return
      }

      await recorder.append(update)
    }

    private func describe(_ update: WidgetTreeUpdate) -> String {
      switch update.type {
      case .subscriptions:
        return "subscriptions:\(update.subscribedEvents.joined(separator: ","))"
      case .ready:
        return "ready"
      case .clearRoot:
        return "clear_root:\(update.clearRootID ?? "unknown")"
      case .commandRequest:
        if let request = update.commandRequestPayload {
          return
            "command_request:\(request.command):sync=\(request.isSynchronous):timeout=\(String(describing: request.timeoutSeconds)):max_output=\(String(describing: request.maxOutputBytes))"
        }
        return "command_request"
      case .commandCancel:
        return "command_cancel:\(update.commandCancelToken ?? "unknown")"
      case .timerRequest:
        return
          "timer_request:\(update.token ?? "unknown"):\(String(describing: update.delaySeconds))"
      case .timerCancel:
        return "timer_cancel:\(update.timerCancelToken ?? "unknown")"
      case .inboxReplace:
        return "inbox_replace:\(update.source ?? "unknown"):\(update.items?.count ?? 0)"
      case .inboxClear:
        return "inbox_clear:\(update.source ?? "unknown")"
      case .inboxConfigure:
        return "inbox_configure:\(update.source ?? "unknown"):\(update.actions?.count ?? 0)"
      case .storageRequest:
        return "storage_request:\(update.widget ?? "unknown"):\(update.key ?? "unknown")"
      case .tree:
        if let payload = update.treePayload,
          let root = payload.nodes.first(where: { $0.id == payload.root })
        {
          return "tree:\(payload.root):icon=\(root.icon):text=\(root.text)"
        }
        return "tree"
      }
    }

    private func sendCommandResponse(token: String, output: String, status: Int) throws {
      let payload = """
        {"protocol_version":1,"type":"command_response","token":"\(token)","output":"\(output)","status":\(status),"duration_ms":1}
        \n
        """
      try stdinHandle.write(contentsOf: Data(payload.utf8))
    }

    private func sendStorageResponse(
      token: String,
      found: Bool,
      value: WidgetStorageValue?
    ) throws {
      let payload = try JSONEncoder().encode(
        StorageResponse(token: token, found: found, value: value)
      )
      try stdinHandle.write(contentsOf: payload + Data("\n".utf8))
    }
  }

  actor RuntimeUpdateRecorder {
    private var updates: [WidgetTreeUpdate] = []
    private var commandRequests: [RuntimeCommandRequest] = []
    private var summaries: [String] = []

    func append(_ update: WidgetTreeUpdate) {
      updates.append(update)
    }

    func append(_ request: RuntimeCommandRequest) {
      commandRequests.append(request)
    }

    func record(summary: String) {
      summaries.append(summary)
    }

    func takeFirst(
      matching predicate: @escaping @Sendable (WidgetTreeUpdate) -> Bool
    ) -> WidgetTreeUpdate? {
      guard let index = updates.firstIndex(where: predicate) else {
        return nil
      }

      let update = updates[index]
      updates.remove(at: index)
      return update
    }

    func debugSummaries() -> [String] {
      summaries
    }

    func takeFirstCommandRequest(
      matching predicate: @escaping @Sendable (RuntimeCommandRequest) -> Bool
    ) -> RuntimeCommandRequest? {
      guard let index = commandRequests.firstIndex(where: predicate) else {
        return nil
      }

      let request = commandRequests[index]
      commandRequests.remove(at: index)
      return request
    }
  }

  final class RuntimeProcess {
    private let process = Process()
    private let stdinPipe = Pipe()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private let stdoutObserver: RuntimeLineObserver
    private let stderrObserver: RuntimeLineObserver

    init(
      runtimePath: String,
      widgetsDirectoryURL: URL,
      recorder: RuntimeUpdateRecorder,
      decoder: JSONDecoder,
      environment: [String: String],
      autoRespondToCommands: Bool
    ) throws {
      let hostBridge = RuntimeHostBridge(
        recorder: recorder,
        decoder: decoder,
        stdinHandle: stdinPipe.fileHandleForWriting,
        asyncResponseDelayNanoseconds: 0,
        autoRespondToCommands: autoRespondToCommands
      )

      LuaRenderRuntimeTestCase.configureLuaProcess(
        process,
        arguments: [runtimePath, widgetsDirectoryURL.path, "5", "65536"]
      )
      process.standardInput = stdinPipe
      process.standardOutput = stdoutPipe
      process.standardError = stderrPipe
      process.environment = environment

      stdoutObserver = RuntimeLineObserver { line in
        do {
          try await hostBridge.handleRuntimeLine(line)
        } catch {
          XCTFail("Failed handling runtime update: \(line) error=\(error)")
        }
      }
      stdoutObserver.attach(to: stdoutPipe.fileHandleForReading)

      stderrObserver = RuntimeLineObserver { _ in }
      stderrObserver.attach(to: stderrPipe.fileHandleForReading)

      try process.run()
    }

    func sendHostEvent(_ payload: String) throws {
      try stdinPipe.fileHandleForWriting.write(contentsOf: Data(payload.utf8))
    }

    func sendCommandResponse(token: String, output: String, status: Int) throws {
      let payload = """
        {"protocol_version":1,"type":"command_response","token":"\(token)","output":"\(output)","status":\(status),"duration_ms":1}
        \n
        """
      try sendHostEvent(payload)
    }

    func stop() {
      stdoutObserver.invalidate()
      stderrObserver.invalidate()

      try? stdinPipe.fileHandleForWriting.close()

      terminate(process)
    }
  }

  final class RuntimeLineObserver: @unchecked Sendable {
    private let handleLine: @Sendable (String) async -> Void
    private var buffer = Data()
    private var pendingLineTask: Task<Void, Never>?

    init(handleLine: @escaping @Sendable (String) async -> Void) {
      self.handleLine = handleLine
    }

    func attach(to handle: FileHandle) {
      handle.readabilityHandler = { [weak self] readableHandle in
        guard let self else { return }

        let data = readableHandle.availableData

        if data.isEmpty {
          self.emitBufferedLineIfNeeded()
          readableHandle.readabilityHandler = nil
          return
        }

        self.buffer.append(data)

        while let newlineIndex = self.buffer.firstIndex(of: 0x0A) {
          let lineData = self.buffer.prefix(upTo: newlineIndex)
          self.buffer.removeSubrange(...newlineIndex)

          guard
            let line = String(data: lineData, encoding: .utf8)?
              .trimmingCharacters(in: .whitespacesAndNewlines),
            !line.isEmpty
          else {
            continue
          }

          self.enqueue(line)
        }
      }
    }

    func invalidate() {
      buffer.removeAll()
      pendingLineTask?.cancel()
      pendingLineTask = nil
    }

    private func emitBufferedLineIfNeeded() {
      guard
        let line = String(data: buffer, encoding: .utf8)?
          .trimmingCharacters(in: .whitespacesAndNewlines),
        !line.isEmpty
      else {
        buffer.removeAll()
        return
      }

      buffer.removeAll()
      enqueue(line)
    }

    private func enqueue(_ line: String) {
      let previousTask = pendingLineTask

      pendingLineTask = Task {
        _ = await previousTask?.result

        guard !Task.isCancelled else {
          return
        }

        await handleLine(line)
      }
    }
  }

  func nextTreeUpdate(
    from recorder: RuntimeUpdateRecorder,
    matching predicate: @escaping @Sendable (WidgetTreeUpdate) -> Bool,
    timeoutNanoseconds: UInt64 = 2_000_000_000
  ) async throws -> WidgetTreeUpdate {
    return try await nextUpdate(
      from: recorder,
      matching: predicate,
      timeoutNanoseconds: timeoutNanoseconds
    )
  }

  func nextUpdate(
    from recorder: RuntimeUpdateRecorder,
    matching predicate: @escaping @Sendable (WidgetTreeUpdate) -> Bool,
    timeoutNanoseconds: UInt64 = 2_000_000_000
  ) async throws -> WidgetTreeUpdate {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds

    while DispatchTime.now().uptimeNanoseconds < deadline {
      if let update = await recorder.takeFirst(matching: predicate) {
        return update
      }

      try await Task.sleep(nanoseconds: 10_000_000)
    }

    let summaries = await recorder.debugSummaries().joined(separator: " | ")

    throw NSError(
      domain: "LuaRenderCoalescingTests",
      code: 1,
      userInfo: [
        NSLocalizedDescriptionKey:
          "Timed out waiting for matching widget tree update; seen updates: \(summaries)"
      ]
    )
  }

  func nextCommandRequest(
    from recorder: RuntimeUpdateRecorder,
    matching predicate: @escaping @Sendable (RuntimeCommandRequest) -> Bool,
    timeoutNanoseconds: UInt64 = 2_000_000_000
  ) async throws -> RuntimeCommandRequest {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds

    while DispatchTime.now().uptimeNanoseconds < deadline {
      if let request = await recorder.takeFirstCommandRequest(matching: predicate) {
        return request
      }

      try await Task.sleep(nanoseconds: 10_000_000)
    }

    let summaries = await recorder.debugSummaries().joined(separator: " | ")

    throw NSError(
      domain: "LuaRenderCoalescingTests",
      code: 2,
      userInfo: [
        NSLocalizedDescriptionKey:
          "Timed out waiting for matching command request; seen updates: \(summaries)"
      ]
    )
  }

  func expectNoUpdate(
    from recorder: RuntimeUpdateRecorder,
    matching predicate: @escaping @Sendable (WidgetTreeUpdate) -> Bool,
    timeoutNanoseconds: UInt64 = 300_000_000
  ) async throws {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds

    while DispatchTime.now().uptimeNanoseconds < deadline {
      if let update = await recorder.takeFirst(matching: predicate) {
        throw NSError(
          domain: "LuaRenderCoalescingTests",
          code: 3,
          userInfo: [
            NSLocalizedDescriptionKey: "Unexpected update: \(update.type)"
          ]
        )
      }

      try await Task.sleep(nanoseconds: 10_000_000)
    }
  }

  func rootNode(in update: WidgetTreeUpdate) -> WidgetNodeState? {
    guard let payload = update.treePayload else {
      return nil
    }

    return payload.nodes.first(where: { $0.id == payload.root })
  }

  func makeTemporaryDirectory() throws -> URL {
    let directoryURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "easybar-lua-render-coalescing-tests-\(UUID().uuidString)",
        isDirectory: true
      )

    try FileManager.default.createDirectory(
      at: directoryURL,
      withIntermediateDirectories: true
    )

    return directoryURL
  }

  func makeWidgetsDirectory() throws -> URL {
    let widgetsDirectoryURL = tempDirectoryURL.appendingPathComponent(
      "widgets",
      isDirectory: true
    )

    try FileManager.default.createDirectory(
      at: widgetsDirectoryURL,
      withIntermediateDirectories: true
    )

    return widgetsDirectoryURL
  }

  static func configureLuaProcess(_ process: Process, arguments: [String]) {
    let luaPath = SharedPathDefaults.defaultLuaPath

    if luaPath.contains("/") {
      process.executableURL = URL(fileURLWithPath: luaPath)
      process.arguments = arguments
      return
    }

    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [luaPath] + arguments
  }

  func luaRuntimeEnvironment(
    for widgetsDirectoryURL: URL
  ) throws -> [String: String] {
    try writeTestConfig(widgetsDirectoryURL: widgetsDirectoryURL)

    var environment = ProcessInfo.processInfo.environment

    // Clean up any existing EasyBar environment variables.
    for key in Array(environment.keys) where key.hasPrefix("EASYBAR_") {
      environment.removeValue(forKey: key)
    }

    // Clean up any existing shared runtime environment variables.
    for key in sharedRuntimeEnvironmentKeys {
      environment.removeValue(forKey: key)
    }

    environment[SharedEnvironmentKeys.configPath] = configFileURL.path

    // Merge in the theme environment.
    environment.merge(Config.makeUnloadedConfig().luaThemeEnvironment()) {
      _, testValue in testValue
    }

    return environment
  }

  var sharedRuntimeEnvironmentKeys: [String] {
    [
      SharedEnvironmentKeys.configPath
    ]
  }

  func writeTestConfig(widgetsDirectoryURL: URL) throws {
    try FileManager.default.createDirectory(
      at: widgetsDirectoryURL,
      withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
      at: lockDirectoryURL,
      withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
      at: loggingDirectoryURL,
      withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
      at: runtimeDirectoryURL,
      withIntermediateDirectories: true
    )

    let luaSocketPath = runtimeDirectoryURL.appendingPathComponent("lua.sock").path
    let calendarSocketPath = runtimeDirectoryURL.appendingPathComponent("calendar.sock").path
    let networkSocketPath = runtimeDirectoryURL.appendingPathComponent("network.sock").path

    try """
    [app]
    widgets_dir = "\(tomlEscaped(widgetsDirectoryURL.path))"
    lua_path = "\(tomlEscaped(SharedPathDefaults.defaultLuaPath))"
    lua_socket_path = "\(tomlEscaped(luaSocketPath))"
    watch_config = false
    lock_dir = "\(tomlEscaped(lockDirectoryURL.path))"
    develop = false

    [logging]
    enabled = false
    level = "error"
    directory = "\(tomlEscaped(loggingDirectoryURL.path))"

    [agents.calendar]
    enabled = false
    socket_path = "\(tomlEscaped(calendarSocketPath))"

    [agents.network]
    enabled = false
    socket_path = "\(tomlEscaped(networkSocketPath))"
    refresh_interval_seconds = 60
    allow_unauthorized_non_sensitive_fields = false
    """.write(to: configFileURL, atomically: true, encoding: .utf8)
  }

  func tomlEscaped(_ value: String) -> String {
    return
      value
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
  }
}

/// Terminates one spawned runtime process without risking an indefinite wait in CI.
func terminate(_ process: Process, gracePeriodNanoseconds: UInt64 = 500_000_000) {
  guard process.isRunning else {
    return
  }

  process.terminate()
  waitForProcessExit(process, timeoutNanoseconds: gracePeriodNanoseconds)

  guard process.isRunning else {
    return
  }

  kill(process.processIdentifier, SIGKILL)
  waitForProcessExit(process, timeoutNanoseconds: gracePeriodNanoseconds)
}

/// Waits briefly for a process to exit without blocking the test process indefinitely.
func waitForProcessExit(_ process: Process, timeoutNanoseconds: UInt64) {
  let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds

  while process.isRunning && DispatchTime.now().uptimeNanoseconds < deadline {
    usleep(10_000)
  }
}
