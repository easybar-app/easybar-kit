import Darwin
import Dispatch
import EasyBarShared
import Foundation
import XCTest

@testable import EasyBarApp
@testable import EasyBarCalendarCore
@testable import EasyBarCtl
@testable import EasyBarNetworkAgentCore

final class LogStreamingTests: XCTestCase {
  private var directoryURL: URL!
  private var socketPath: String!

  override func setUpWithError() throws {
    try super.setUpWithError()
    let suffix = UUID().uuidString.prefix(12)
    directoryURL = URL(fileURLWithPath: "/tmp/eb-log-\(suffix)", isDirectory: true)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    socketPath = directoryURL.appendingPathComponent("easybar.sock").path
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directoryURL)
    socketPath = nil
    directoryURL = nil
    try super.tearDownWithError()
  }

  func testLogSubscriptionRequestRoundTrips() throws {
    let request = IPC.Request.makeLogs(
      IPC.LogSubscription(
        widget: "brew-inbox",
        runtime: .lua,
        minimumLevel: .trace,
        requestID: "lua-42"
      )
    )

    let data = try JSONEncoder().encode(request)
    let decoded = try JSONDecoder().decode(IPC.Request.self, from: data)

    guard case .logs(let subscription) = decoded else {
      return XCTFail("expected logs request")
    }
    XCTAssertEqual(subscription.widget, "brew-inbox")
    XCTAssertEqual(subscription.runtime, .lua)
    XCTAssertEqual(subscription.minimumLevel, .trace)
    XCTAssertEqual(subscription.requestID, "lua-42")
  }

  func testCalendarAgentLogSubscriptionRequestRoundTrips() throws {
    let request = CalendarAgentRequest.logs(
      IPC.LogSubscription(runtime: .agent, minimumLevel: .debug)
    )

    let data = try JSONEncoder().encode(request)
    let decoded = try JSONDecoder().decode(CalendarAgentRequest.self, from: data)

    XCTAssertEqual(decoded, request)
    XCTAssertEqual(decoded.command, .logs)
    XCTAssertEqual(decoded.logSubscription?.runtime, .agent)
    XCTAssertEqual(decoded.logSubscription?.minimumLevel, .debug)
  }

  func testNetworkAgentLogSubscriptionRequestRoundTrips() throws {
    let request = NetworkAgentRequest.logs(
      IPC.LogSubscription(
        runtime: .agent,
        minimumLevel: .trace,
        requestID: "network-live-test"
      )
    )

    let data = try JSONEncoder().encode(request)
    let decoded = try JSONDecoder().decode(NetworkAgentRequest.self, from: data)

    XCTAssertEqual(decoded.command, .logs)
    XCTAssertEqual(decoded.logSubscription?.runtime, .agent)
    XCTAssertEqual(decoded.logSubscription?.minimumLevel, .trace)
  }

  func testAgentLogMessagesRoundTrip() throws {
    let event = ProcessLogEvent(
      timestamp: Date(timeIntervalSince1970: 1_700_000_000),
      timestampText: "2023-11-14T22:13:20.000Z",
      level: .trace,
      message: "agent trace",
      fields: ["runtime": "agent"],
      source: "calendar-agent",
      rawLine: "[2023-11-14T22:13:20.000Z] [TRACE] agent trace runtime=agent"
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let calendar = try decoder.decode(
      CalendarAgentMessage.self,
      from: encoder.encode(CalendarAgentMessage(kind: .logRecord, logRecord: event))
    )
    let network = try decoder.decode(
      NetworkAgentMessage.self,
      from: encoder.encode(NetworkAgentMessage(kind: .logRecord, logRecord: event))
    )

    XCTAssertEqual(calendar.kind, .logRecord)
    XCTAssertEqual(calendar.logRecord?.message, "agent trace")
    XCTAssertEqual(network.kind, .logRecord)
    XCTAssertEqual(network.logRecord?.message, "agent trace")
  }

  func testBareLogsRequestUsesDefaultSubscription() throws {
    let decoded = try JSONDecoder().decode(
      IPC.Request.self,
      from: Data(#"{"command":"logs"}"#.utf8)
    )

    guard case .logs(let subscription) = decoded else {
      return XCTFail("expected logs request")
    }
    XCTAssertNil(subscription.widget)
    XCTAssertNil(subscription.runtime)
    XCTAssertNil(subscription.minimumLevel)
    XCTAssertNil(subscription.requestID)
  }

  func testTraceSubscriptionDoesNotChangeConfiguredLoggerLevel() throws {
    let logger = ProcessLogger(
      label: "easybar",
      minimumLevel: .info,
      outputStream: nil,
      errorStream: nil
    )
    let server = SocketServer(logger: logger.child("socket_server"), socketPath: socketPath)
    XCTAssertTrue(
      server.start(handler: { _ in }, validateConfigHandler: { _ in .rejected(message: "unused") })
    )
    defer { server.stop() }

    let fd = try openConnectedUnixSocket(at: socketPath, timeout: 1)
    defer { close(fd) }

    try Self.send(
      IPC.Request.makeLogs(
        IPC.LogSubscription(
          widget: "brew-inbox",
          runtime: .lua,
          minimumLevel: .trace
        )
      ),
      to: fd
    )
    _ = try Self.readLogSubscriptionAcknowledgement(from: fd)
    usleep(10_000)

    logger.trace(
      "live trace",
      .field("widget", "brew-inbox"),
      .field("runtime", ProcessLogRuntime.lua.rawValue)
    )

    let event = try Self.readLogRecord(message: "live trace", from: fd)

    XCTAssertEqual(event.level, .trace)
    XCTAssertEqual(event.message, "live trace")
    XCTAssertEqual(event.widget, "brew-inbox")
    XCTAssertEqual(event.runtime, .lua)
    XCTAssertEqual(logger.minimumLevel, .info)
  }

  @MainActor
  func testCalendarAgentStreamsTraceWithoutPersistingTrace() async throws {
    let logger = ProcessLogger(
      label: "easybar-calendar-agent",
      minimumLevel: .info,
      outputStream: nil,
      errorStream: nil
    )
    let agentSocketPath = directoryURL.appendingPathComponent("calendar-agent.sock").path
    let provider = CalendarSnapshotProvider(
      logger: logger.child("provider"),
      authorizationStatus: { .denied }
    )
    let server = CalendarSocketServer(
      socketPath: agentSocketPath,
      appVersion: "test",
      logger: logger.child("socket_server"),
      onRestartRequested: {}
    )
    XCTAssertTrue(server.start(provider: provider))
    defer { server.stop() }

    let message = try await Self.runBlocking {
      let fd = try openConnectedUnixSocket(at: agentSocketPath, timeout: 1)
      defer { close(fd) }

      try Self.send(
        CalendarAgentRequest.logs(
          IPC.LogSubscription(
            runtime: .agent,
            minimumLevel: .trace,
            requestID: "calendar-live-test"
          )
        ),
        to: fd
      )
      let acknowledgement = try Self.readCalendarLogSubscriptionAcknowledgement(from: fd)

      logger.trace(
        "calendar live trace",
        .field("request_id", "calendar-live-test")
      )
      let record = try Self.readCalendarLogRecord(message: "calendar live trace", from: fd)
      return (acknowledgement, record)
    }

    XCTAssertEqual(message.0.kind, .logSubscribed)
    XCTAssertEqual(message.1.kind, .logRecord)
    XCTAssertEqual(message.1.logRecord?.message, "calendar live trace")
    XCTAssertEqual(message.1.logRecord?.runtime, .agent)
    XCTAssertEqual(logger.minimumLevel, .info)
  }

  @MainActor
  func testNetworkAgentStreamsTraceWithoutPersistingTrace() async throws {
    let logger = ProcessLogger(
      label: "easybar-network-agent",
      minimumLevel: .info,
      outputStream: nil,
      errorStream: nil
    )
    let agentSocketPath = directoryURL.appendingPathComponent("network-agent.sock").path
    let provider = NetworkSnapshotProvider(
      componentName: "network agent tests",
      refreshIntervalSeconds: 0,
      logger: logger.child("provider")
    )
    let server = NetworkSocketServer(
      componentName: "network agent tests",
      socketPath: agentSocketPath,
      appVersion: "test",
      allowUnauthorizedNonSensitiveFields: false,
      logger: logger.child("socket_server"),
      onRestartRequested: {}
    )
    XCTAssertTrue(server.start(provider: provider))
    defer { server.stop() }

    let message = try await Self.runBlocking {
      let fd = try openConnectedUnixSocket(at: agentSocketPath, timeout: 1)
      defer { close(fd) }

      try Self.send(
        NetworkAgentRequest.logs(
          IPC.LogSubscription(
            runtime: .agent,
            minimumLevel: .trace,
            requestID: "network-live-test"
          )
        ),
        to: fd
      )
      let acknowledgement = try Self.readNetworkLogSubscriptionAcknowledgement(from: fd)

      logger.trace(
        "network live trace",
        .field("request_id", "network-live-test")
      )
      let record = try Self.readNetworkLogRecord(message: "network live trace", from: fd)
      return (acknowledgement, record)
    }

    XCTAssertEqual(message.0.kind, .logSubscribed)
    XCTAssertEqual(message.1.kind, .logRecord)
    XCTAssertEqual(message.1.logRecord?.message, "network live trace")
    XCTAssertEqual(message.1.logRecord?.runtime, .agent)
    XCTAssertEqual(logger.minimumLevel, .info)
  }

  func testMetricsBroadcastDoesNotReachLogSubscriber() async throws {
    let logger = ProcessLogger(
      label: "easybar",
      minimumLevel: .info,
      outputStream: nil,
      errorStream: nil
    )
    let server = SocketServer(logger: logger.child("socket_server"), socketPath: socketPath)
    XCTAssertTrue(
      server.start(handler: { _ in }, validateConfigHandler: { _ in .rejected(message: "unused") })
    )
    defer { server.stop() }

    let fd = try openConnectedUnixSocket(at: socketPath, timeout: 1)
    defer { close(fd) }

    try Self.send(
      IPC.Request.makeLogs(IPC.LogSubscription(minimumLevel: .trace)),
      to: fd
    )
    _ = try Self.readLogSubscriptionAcknowledgement(from: fd)
    usleep(10_000)

    server.broadcastMetrics(await MetricsCoordinator.shared.snapshot())
    try Self.assertNoMetricsMessage(from: fd, timeoutMilliseconds: 50)

    logger.trace("live trace after metrics")
    let event = try Self.readLogRecord(message: "live trace after metrics", from: fd)
    XCTAssertEqual(event.message, "live trace after metrics")
  }

  private static func runBlocking<T: Sendable>(
    _ operation: @escaping @Sendable () throws -> T
  ) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
      DispatchQueue.global(qos: .userInitiated).async {
        continuation.resume(with: Result(catching: operation))
      }
    }
  }

  private static func readLogSubscriptionAcknowledgement(from fd: Int32) throws -> IPC.Message {
    for _ in 0..<64 {
      let message = try Self.readMessage(IPC.Message.self, from: fd, timeoutMilliseconds: 1_000)
      switch message {
      case .logSubscribed:
        return message
      case .logRecord:
        continue
      default:
        throw Self.unexpectedMessage("expected log_subscribed, received \(message.kind.rawValue)")
      }
    }

    throw Self.unexpectedMessage("log_subscribed was not received")
  }

  private static func readLogRecord(message expectedMessage: String, from fd: Int32) throws
    -> ProcessLogEvent
  {
    for _ in 0..<64 {
      let message = try Self.readMessage(IPC.Message.self, from: fd, timeoutMilliseconds: 1_000)
      switch message {
      case .logRecord(let event) where event.message == expectedMessage:
        return event
      case .logRecord, .logSubscribed:
        continue
      default:
        throw Self.unexpectedMessage(
          "expected log_record '\(expectedMessage)', received \(message.kind.rawValue)"
        )
      }
    }

    throw Self.unexpectedMessage("log_record '\(expectedMessage)' was not received")
  }

  private static func readCalendarLogSubscriptionAcknowledgement(from fd: Int32) throws
    -> CalendarAgentMessage
  {
    for _ in 0..<64 {
      let message = try Self.readMessage(
        CalendarAgentMessage.self,
        from: fd,
        timeoutMilliseconds: 1_000
      )
      switch message.kind {
      case .logSubscribed:
        return message
      case .logRecord:
        continue
      default:
        throw Self.unexpectedMessage(
          "expected calendar log_subscribed, received \(message.kind.rawValue)"
        )
      }
    }

    throw Self.unexpectedMessage("calendar log_subscribed was not received")
  }

  private static func readCalendarLogRecord(message expectedMessage: String, from fd: Int32) throws
    -> CalendarAgentMessage
  {
    for _ in 0..<64 {
      let message = try Self.readMessage(
        CalendarAgentMessage.self,
        from: fd,
        timeoutMilliseconds: 1_000
      )
      switch message.kind {
      case .logRecord where message.logRecord?.message == expectedMessage:
        return message
      case .logRecord, .logSubscribed:
        continue
      default:
        throw Self.unexpectedMessage(
          "expected calendar log_record '\(expectedMessage)', received \(message.kind.rawValue)"
        )
      }
    }

    throw Self.unexpectedMessage("calendar log_record '\(expectedMessage)' was not received")
  }

  private static func readNetworkLogSubscriptionAcknowledgement(from fd: Int32) throws
    -> NetworkAgentMessage
  {
    for _ in 0..<64 {
      let message = try Self.readMessage(
        NetworkAgentMessage.self,
        from: fd,
        timeoutMilliseconds: 1_000
      )
      switch message.kind {
      case .logSubscribed:
        return message
      case .logRecord:
        continue
      default:
        throw Self.unexpectedMessage(
          "expected network log_subscribed, received \(message.kind.rawValue)"
        )
      }
    }

    throw Self.unexpectedMessage("network log_subscribed was not received")
  }

  private static func readNetworkLogRecord(message expectedMessage: String, from fd: Int32) throws
    -> NetworkAgentMessage
  {
    for _ in 0..<64 {
      let message = try Self.readMessage(
        NetworkAgentMessage.self,
        from: fd,
        timeoutMilliseconds: 1_000
      )
      switch message.kind {
      case .logRecord where message.logRecord?.message == expectedMessage:
        return message
      case .logRecord, .logSubscribed:
        continue
      default:
        throw Self.unexpectedMessage(
          "expected network log_record '\(expectedMessage)', received \(message.kind.rawValue)"
        )
      }
    }

    throw Self.unexpectedMessage("network log_record '\(expectedMessage)' was not received")
  }

  private static func assertNoMetricsMessage(from fd: Int32, timeoutMilliseconds: Int32) throws {
    let deadline = Date().addingTimeInterval(Double(timeoutMilliseconds) / 1_000)

    while true {
      let remaining = deadline.timeIntervalSinceNow
      guard remaining > 0 else { return }

      var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
      let remainingMilliseconds = max(1, Int32((remaining * 1_000).rounded(.up)))
      let result = Darwin.poll(&descriptor, 1, remainingMilliseconds)

      if result == 0 { return }
      if result < 0 {
        if errno == EINTR { continue }
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
      }

      let message = try Self.readMessage(from: fd)
      if case .metrics = message {
        throw Self.unexpectedMessage("metrics payload reached log subscriber")
      }
    }
  }

  private static func send<Request: Encodable>(_ request: Request, to fd: Int32) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(request) + Data([0x0A])
    if let error = writeAll(data, to: fd, timeout: 1) {
      throw error
    }
  }

  private static func readMessage(from fd: Int32) throws -> IPC.Message {
    try Self.readMessage(IPC.Message.self, from: fd)
  }

  private static func readCalendarMessage(from fd: Int32) throws -> CalendarAgentMessage {
    try Self.readMessage(CalendarAgentMessage.self, from: fd)
  }

  private static func readNetworkMessage(from fd: Int32) throws -> NetworkAgentMessage {
    try Self.readMessage(NetworkAgentMessage.self, from: fd)
  }

  private static func readMessage<Message: Decodable>(
    _ type: Message.Type,
    from fd: Int32,
    timeoutMilliseconds: Int32
  ) throws -> Message {
    var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)

    while true {
      let result = Darwin.poll(&descriptor, 1, timeoutMilliseconds)
      if result > 0 {
        return try Self.readMessage(type, from: fd)
      }
      if result == 0 {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(ETIMEDOUT))
      }
      if errno != EINTR {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
      }
    }
  }

  private static func unexpectedMessage(_ description: String) -> NSError {
    NSError(
      domain: "LogStreamingTests",
      code: 1,
      userInfo: [NSLocalizedDescriptionKey: description]
    )
  }

  private static func readMessage<Message: Decodable>(
    _ type: Message.Type,
    from fd: Int32
  ) throws -> Message {
    var bytes: [UInt8] = []
    var byte: UInt8 = 0

    while true {
      let count = Darwin.read(fd, &byte, 1)
      guard count > 0 else {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
      }
      if byte == 0x0A { break }
      bytes.append(byte)
    }

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(type, from: Data(bytes))
  }
}


