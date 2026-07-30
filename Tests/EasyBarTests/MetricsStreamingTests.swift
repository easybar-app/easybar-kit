import Darwin
import EasyBarShared
import Foundation
import XCTest

@testable import EasyBarApp

final class MetricsStreamingTests: XCTestCase {
  private var socketDirectoryURL: URL!
  private var socketPath: String!

  override func setUpWithError() throws {
    try super.setUpWithError()

    socketDirectoryURL = URL(fileURLWithPath: "/tmp", isDirectory: true)
      .appendingPathComponent("easybar-metrics-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: socketDirectoryURL,
      withIntermediateDirectories: true
    )

    socketPath = socketDirectoryURL.appendingPathComponent("easybar.sock").path
  }

  override func tearDownWithError() throws {
    if let socketDirectoryURL {
      try? FileManager.default.removeItem(at: socketDirectoryURL)
    }
    try super.tearDownWithError()
  }

  func testMetricsWatchStopsSamplingAfterClientDisconnects() async throws {
    await MetricsCoordinator.shared.resetStreaming()
    defer {
      Task {
        await MetricsCoordinator.shared.resetStreaming()
      }
    }

    let server = SocketServer(
      logger: ProcessLogger(label: "metrics.streaming.tests", minimumLevel: .error),
      socketPath: socketPath
    )
    server.start(handler: { _ in }, validateConfigHandler: { _ in .rejected(message: "unused") })
    defer { server.stop() }

    var clientFD = try connectUnixSocket(path: socketPath)
    defer {
      if clientFD >= 0 {
        shutdown(clientFD, SHUT_RDWR)
        close(clientFD)
      }
    }

    try sendMetricsWatchRequest(to: clientFD)
    _ = try readLine(from: clientFD)

    try await waitUntil("metrics streaming to start") {
      await MetricsCoordinator.shared.isStreamingActive
    }

    shutdown(clientFD, SHUT_RDWR)
    close(clientFD)
    clientFD = -1

    try await waitUntil("metrics streaming to stop") {
      !(await MetricsCoordinator.shared.isStreamingActive)
    }
  }

  func testMetricsBroadcastDoesNotBlockOnNonReadingSubscriber() async throws {
    await MetricsCoordinator.shared.resetStreaming()
    defer {
      Task {
        await MetricsCoordinator.shared.resetStreaming()
      }
    }

    let server = SocketServer(
      logger: ProcessLogger(label: "metrics.streaming.tests", minimumLevel: .error),
      socketPath: socketPath
    )
    server.start(handler: { _ in }, validateConfigHandler: { _ in .rejected(message: "unused") })
    defer { server.stop() }

    let clientFD = try connectUnixSocket(path: socketPath)
    defer {
      shutdown(clientFD, SHUT_RDWR)
      close(clientFD)
    }
    var receiveBufferSize: Int32 = 1_024
    XCTAssertEqual(
      setsockopt(
        clientFD,
        SOL_SOCKET,
        SO_RCVBUF,
        &receiveBufferSize,
        socklen_t(MemoryLayout<Int32>.size)
      ),
      0
    )

    try sendMetricsWatchRequest(to: clientFD)
    _ = try readLine(from: clientFD)

    let snapshot = await MetricsCoordinator.shared.snapshot()
    let startedAt = Date()
    for _ in 0..<512 {
      server.broadcastMetrics(snapshot)
    }

    XCTAssertLessThan(Date().timeIntervalSince(startedAt), 0.5)
  }

  func testValidateConfigRequestReturnsValidatedPath() async throws {
    await MetricsCoordinator.shared.resetStreaming()
    defer {
      Task {
        await MetricsCoordinator.shared.resetStreaming()
      }
    }

    let server = SocketServer(
      logger: ProcessLogger(label: "metrics.streaming.tests", minimumLevel: .error),
      socketPath: socketPath
    )
    server.start(
      handler: { _ in },
      validateConfigHandler: { configPath in
        .configValidated(configPath: configPath ?? "<default>", warnings: [])
      }
    )
    defer { server.stop() }

    let client = LineSocketClientTransport<IPC.Request, IPC.Message>(socketPath: socketPath)
    let configPath = socketDirectoryURL.appendingPathComponent("config.toml").path

    let response = try client.send(request: .makeValidateConfig(configPath: configPath))

    guard case .configValidated(let validatedPath, let warnings) = response else {
      return XCTFail("Expected configValidated response, got \(response)")
    }

    XCTAssertEqual(validatedPath, configPath)
    XCTAssertEqual(warnings, [])
  }

  func testInboxRequestUsesTypedHandlerAndResponse() throws {
    let server = SocketServer(
      logger: ProcessLogger(label: "inbox.socket.tests", minimumLevel: .error),
      socketPath: socketPath
    )
    let item = IPC.InboxItem(
      source: "backup",
      id: "nightly",
      title: "Backup failed",
      severity: .error,
      timestamp: 123
    )
    server.start(
      handler: { _ in },
      validateConfigHandler: { _ in .rejected(message: "unused") },
      inboxHandler: { request in
        guard request.operation == .read else {
          return .rejected(message: "unexpected operation")
        }
        return .inbox([item])
      }
    )
    defer { server.stop() }

    let client = LineSocketClientTransport<IPC.Request, IPC.Message>(socketPath: socketPath)
    let response = try client.send(request: .makeInbox(.init(operation: .read)))

    guard case .inbox(let items) = response else {
      return XCTFail("Expected inbox response")
    }
    XCTAssertEqual(items, [item])
  }

  func testDuplicateSocketServerStartKeepsExistingListener() throws {
    let server = SocketServer(
      logger: ProcessLogger(label: "metrics.streaming.tests", minimumLevel: .error),
      socketPath: socketPath
    )
    server.start(
      handler: { _ in },
      validateConfigHandler: { configPath in
        .configValidated(configPath: configPath ?? "<default>", warnings: [])
      }
    )
    server.start(
      handler: { _ in },
      validateConfigHandler: { _ in .rejected(message: "duplicate start should be ignored") }
    )
    defer { server.stop() }

    let client = LineSocketClientTransport<IPC.Request, IPC.Message>(socketPath: socketPath)
    let configPath = socketDirectoryURL.appendingPathComponent("duplicate-start.toml").path

    let response = try client.send(request: .makeValidateConfig(configPath: configPath))

    guard case .configValidated(let validatedPath, let warnings) = response else {
      return XCTFail("Expected configValidated response, got \(response)")
    }

    XCTAssertEqual(validatedPath, configPath)
    XCTAssertEqual(warnings, [])
  }

  func testSocketServerCanRetryAfterListenerSetupFailure() throws {
    FileManager.default.createFile(atPath: socketPath, contents: Data())

    let server = SocketServer(
      logger: ProcessLogger(label: "metrics.streaming.tests", minimumLevel: .error),
      socketPath: socketPath
    )
    server.start(handler: { _ in }, validateConfigHandler: { _ in .rejected(message: "unused") })

    try FileManager.default.removeItem(atPath: socketPath)
    server.start(
      handler: { _ in },
      validateConfigHandler: { configPath in
        .configValidated(configPath: configPath ?? "<default>", warnings: [])
      }
    )
    defer { server.stop() }

    let client = LineSocketClientTransport<IPC.Request, IPC.Message>(socketPath: socketPath)
    let response = try client.send(request: .makeValidateConfig(configPath: nil))

    guard case .configValidated(let validatedPath, _) = response else {
      return XCTFail("Expected configValidated response, got \(response)")
    }

    XCTAssertEqual(validatedPath, "<default>")
  }

  func testSamePathReloadRetriesFailedInitialListener() throws {
    FileManager.default.createFile(atPath: socketPath, contents: Data())

    let server = SocketServer(
      logger: ProcessLogger(label: "metrics.streaming.tests", minimumLevel: .error),
      socketPath: socketPath
    )
    XCTAssertFalse(
      server.start(
        handler: { _ in },
        validateConfigHandler: { configPath in
          .configValidated(configPath: configPath ?? "<default>", warnings: [])
        }
      )
    )

    try FileManager.default.removeItem(atPath: socketPath)
    XCTAssertEqual(server.reloadConfiguration(socketPath: socketPath), .rebound)
    defer { server.stop() }

    let client = LineSocketClientTransport<IPC.Request, IPC.Message>(socketPath: socketPath)
    let response = try client.send(request: .makeValidateConfig(configPath: nil))

    guard case .configValidated(let validatedPath, _) = response else {
      return XCTFail("Expected configValidated response, got \(response)")
    }
    XCTAssertEqual(validatedPath, "<default>")
  }

  func testReloadKeepsNewMetricsSubscriberActive() async throws {
    await MetricsCoordinator.shared.resetStreaming()

    let server = SocketServer(
      logger: ProcessLogger(label: "metrics.streaming.tests", minimumLevel: .error),
      socketPath: socketPath
    )
    server.start(handler: { _ in }, validateConfigHandler: { _ in .rejected(message: "unused") })
    defer { server.stop() }

    let reloadedSocketPath = socketDirectoryURL.appendingPathComponent("reloaded.sock").path
    XCTAssertEqual(server.reloadConfiguration(socketPath: reloadedSocketPath), .rebound)

    var clientFD = try connectUnixSocket(path: reloadedSocketPath)
    defer {
      if clientFD >= 0 {
        shutdown(clientFD, SHUT_RDWR)
        close(clientFD)
      }
    }

    try sendMetricsWatchRequest(to: clientFD)
    _ = try readLine(from: clientFD)

    try await waitUntil("metrics streaming after socket reload") {
      await MetricsCoordinator.shared.isStreamingActive
    }

    shutdown(clientFD, SHUT_RDWR)
    close(clientFD)
    clientFD = -1
  }

  func testFailedReloadKeepsExistingListenerAndCanRetry() throws {
    let server = SocketServer(
      logger: ProcessLogger(label: "metrics.streaming.tests", minimumLevel: .error),
      socketPath: socketPath
    )
    server.start(
      handler: { _ in },
      validateConfigHandler: { configPath in
        .configValidated(configPath: configPath ?? "<default>", warnings: [])
      }
    )
    defer { server.stop() }

    let reloadedSocketPath = socketDirectoryURL.appendingPathComponent("reloaded.sock").path
    FileManager.default.createFile(atPath: reloadedSocketPath, contents: Data())
    XCTAssertEqual(
      server.reloadConfiguration(socketPath: reloadedSocketPath),
      .failed(requestedPath: reloadedSocketPath)
    )

    let existingClient = LineSocketClientTransport<IPC.Request, IPC.Message>(
      socketPath: socketPath
    )
    let existingResponse = try existingClient.send(request: .makeValidateConfig(configPath: nil))
    guard case .configValidated(let existingPath, _) = existingResponse else {
      return XCTFail("Expected configValidated response, got \(existingResponse)")
    }
    XCTAssertEqual(existingPath, "<default>")

    try FileManager.default.removeItem(atPath: reloadedSocketPath)
    server.reloadConfiguration(socketPath: reloadedSocketPath)

    let client = LineSocketClientTransport<IPC.Request, IPC.Message>(
      socketPath: reloadedSocketPath
    )
    let response = try client.send(request: .makeValidateConfig(configPath: nil))

    guard case .configValidated(let validatedPath, _) = response else {
      return XCTFail("Expected configValidated response, got \(response)")
    }

    XCTAssertEqual(validatedPath, "<default>")
  }

  private func connectUnixSocket(path: String) throws -> Int32 {
    let clientFD = socket(AF_UNIX, SOCK_STREAM, 0)
    guard clientFD >= 0 else {
      throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }

    guard configureNoSigPipe(fd: clientFD) else {
      close(clientFD)
      throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }

    var address = try makeSockAddrUn(path: path)
    let addressLength = socklen_t(MemoryLayout<sockaddr_un>.size)

    let didConnect = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        connect(clientFD, $0, addressLength)
      }
    }

    guard didConnect == 0 else {
      let errorCode = errno
      close(clientFD)
      throw NSError(domain: NSPOSIXErrorDomain, code: Int(errorCode))
    }

    return clientFD
  }

  private func sendMetricsWatchRequest(to clientFD: Int32) throws {
    let encoder = JSONEncoder()
    let data = try encoder.encode(IPC.Request.makeMetrics(watch: true)) + Data([0x0A])
    XCTAssertTrue(writeAll(data, to: clientFD))
  }

  private func readLine(from clientFD: Int32) throws -> String {
    var buffer = Data()
    var byte = UInt8(0)

    while true {
      let count = read(clientFD, &byte, 1)

      if count == 1 {
        if byte == 0x0A {
          break
        }

        buffer.append(byte)
        continue
      }

      if count < 0 && errno == EINTR {
        continue
      }

      throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }

    guard let line = String(data: buffer, encoding: .utf8) else {
      XCTFail("Metrics response was not valid UTF-8")
      return ""
    }

    return line
  }

  private func waitUntil(
    _ description: String,
    timeoutNanoseconds: UInt64 = 1_000_000_000,
    condition: @escaping () async -> Bool
  ) async throws {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds

    while DispatchTime.now().uptimeNanoseconds < deadline {
      if await condition() {
        return
      }

      try await Task.sleep(nanoseconds: 10_000_000)
    }

    XCTFail("Timed out waiting for \(description)")
  }
}
