import Darwin
import Foundation
import XCTest

@testable import EasyBarShared

final class AgentSocketClientTests: XCTestCase {
  private struct TestRequest: Codable {
    let command: String
  }

  private struct TestMessage: Codable, Equatable {
    let kind: String
  }

  private struct CallbackCounts {
    var connected = 0
    var disconnected = 0
    var decoded = 0
  }

  private var temporaryDirectory: URL!
  private var socketPath: String!

  override func setUpWithError() throws {
    try super.setUpWithError()

    temporaryDirectory = URL(fileURLWithPath: "/tmp", isDirectory: true)
      .appendingPathComponent("eb-agent-\(UUID().uuidString)", isDirectory: true)

    try FileManager.default.createDirectory(
      at: temporaryDirectory,
      withIntermediateDirectories: true
    )

    socketPath = temporaryDirectory.appendingPathComponent("agent.sock").path
  }

  override func tearDownWithError() throws {
    if let temporaryDirectory {
      try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    socketPath = nil
    temporaryDirectory = nil

    try super.tearDownWithError()
  }

  func testStopRunsDisconnectCallbackForActiveConnection() async throws {
    let logger = Self.makeLogger()
    let server = makeServer(logger: logger)

    server.start { fd, _ in
      server.addSubscriber((), for: fd)
      _ = server.send(TestMessage(kind: "subscribed"), to: fd)
      return .keepOpen
    }
    defer { server.stop() }

    let callbacks = LockedState(CallbackCounts())
    let client = AgentSocketClient<TestRequest, TestMessage>(
      label: "test agent",
      socketPath: { self.socketPath },
      subscribeRequest: { TestRequest(command: "subscribe") },
      handleMessage: { _, _ in
        callbacks.withLock { $0.decoded += 1 }
      },
      clearState: { _ in },
      onConnected: {
        callbacks.withLock { $0.connected += 1 }
      },
      onDisconnected: {
        callbacks.withLock { $0.disconnected += 1 }
      },
      logger: logger
    )

    client.start()
    defer { client.stop() }

    try await waitUntil("client to connect") {
      callbacks.withLock { $0.connected == 1 }
    }
    try await waitUntil("client to decode subscribed message") {
      callbacks.withLock { $0.decoded == 1 }
    }

    client.stop()

    try await waitUntil("client stop to record disconnect") {
      callbacks.withLock { $0.disconnected == 1 }
    }

    XCTAssertFalse(client.isConnected)
  }

  func testDisconnectClearStateCallbackMatchesCurrentRunGeneration() async throws {
    let logger = Self.makeLogger()
    let server = makeServer(logger: logger)

    server.start { fd, _ in
      _ = server.send(TestMessage(kind: "subscribed"), to: fd)
      return .close
    }
    defer { server.stop() }

    let callbackAccepted = LockedState(false)
    let clientBox = LockedState<AgentSocketClient<TestRequest, TestMessage>?>(nil)
    let client = AgentSocketClient<TestRequest, TestMessage>(
      label: "test agent",
      socketPath: { self.socketPath },
      subscribeRequest: { TestRequest(command: "subscribe") },
      handleMessage: { _, _ in },
      clearState: { connectionID in
        let accepted = clientBox.withLock { client in
          client?.isCurrentConnectionGeneration(connectionID) ?? false
        }
        callbackAccepted.withLock { $0 = accepted }
      },
      logger: logger
    )
    clientBox.withLock { $0 = client }
    client.setNextReconnectDelay(30)

    client.start()
    defer { client.stop() }

    try await waitUntil("disconnect clear-state callback") {
      callbackAccepted.withLock { $0 }
    }
  }

  func testMessageIsDroppedWhenConnectionStopsDuringDecodeCallback() async throws {
    let logger = Self.makeLogger()
    let server = makeServer(logger: logger)

    server.start { fd, _ in
      _ = server.send(TestMessage(kind: "subscribed"), to: fd)
      return .keepOpen
    }
    defer { server.stop() }

    let handledMessages = LockedState(0)
    let clientBox = LockedState<AgentSocketClient<TestRequest, TestMessage>?>(nil)
    let client = AgentSocketClient<TestRequest, TestMessage>(
      label: "test agent",
      socketPath: { self.socketPath },
      subscribeRequest: { TestRequest(command: "subscribe") },
      handleMessage: { _, _ in
        handledMessages.withLock { $0 += 1 }
      },
      clearState: { _ in },
      onDecodedMessage: {
        clientBox.withLock { $0 }?.stop()
      },
      logger: logger
    )
    clientBox.withLock { $0 = client }

    client.start()
    defer { client.stop() }

    try await waitUntil("decode callback to stop client") {
      !client.isConnected
    }
    try await Task.sleep(nanoseconds: 50_000_000)

    XCTAssertEqual(handledMessages.withLock { $0 }, 0)
  }

  func testReconnectStaysSuspendedUntilExplicitResume() async throws {
    let logger = Self.makeLogger()
    let server = makeServer(logger: logger)
    let requestCount = LockedState(0)

    server.start { fd, _ in
      requestCount.withLock { $0 += 1 }
      _ = server.send(TestMessage(kind: "permanent_error"), to: fd)
      return .close
    }
    defer { server.stop() }

    let clientBox = LockedState<AgentSocketClient<TestRequest, TestMessage>?>(nil)
    let client = AgentSocketClient<TestRequest, TestMessage>(
      label: "test agent",
      socketPath: { self.socketPath },
      subscribeRequest: { TestRequest(command: "subscribe") },
      handleMessage: { _, _ in
        clientBox.withLock { $0 }?.suspendReconnect()
      },
      clearState: { _ in },
      logger: logger
    )
    clientBox.withLock { $0 = client }
    client.setNextReconnectDelay(0.05)
    client.start()
    defer { client.stop() }

    try await waitUntil("first permanent error and disconnect") {
      requestCount.withLock { $0 == 1 } && !client.isConnected
    }
    try await Task.sleep(nanoseconds: 150_000_000)
    XCTAssertEqual(requestCount.withLock { $0 }, 1)

    client.resumeReconnect()

    try await waitUntil("explicit resume to reconnect") {
      requestCount.withLock { $0 == 2 }
    }
  }

  func testServerStopClosesKeptOpenSubscriberSocket() async throws {
    let logger = Self.makeLogger()
    let removedSubscribers = LockedState(0)

    let notifyingServer = LineSocketServerTransport<Void, TestRequest, TestMessage>(
      socketPath: socketPath,
      serverLabel: "test agent",
      logger: logger,
      onSubscriberRemoved: { _ in
        removedSubscribers.withLock { $0 += 1 }
      }
    )

    notifyingServer.start { fd, _ in
      notifyingServer.addSubscriber((), for: fd)
      _ = notifyingServer.send(TestMessage(kind: "subscribed"), to: fd)
      return .keepOpen
    }
    defer { notifyingServer.stop() }

    let clientFD = try connectUnixSocket()
    defer { close(clientFD) }

    try writeLine(#"{"command":"subscribe"}"#, to: clientFD)

    let response = try readMessage(from: clientFD)
    XCTAssertEqual(response, TestMessage(kind: "subscribed"))

    try await waitUntil("subscriber to stay registered") {
      notifyingServer.subscribersSnapshot().count == 1
    }

    notifyingServer.stop()

    try await waitUntil("server stop to close subscriber socket") {
      self.socketIsClosed(clientFD)
    }
    try await waitUntil("subscriber removal callback") {
      removedSubscribers.withLock { $0 == 1 }
    }
  }

  func testClientDisconnectRemovesKeptOpenSubscriberSocket() async throws {
    let logger = Self.makeLogger()
    let removedSubscribers = LockedState(0)

    let notifyingServer = LineSocketServerTransport<Void, TestRequest, TestMessage>(
      socketPath: socketPath,
      serverLabel: "test agent",
      logger: logger,
      onSubscriberRemoved: { _ in
        removedSubscribers.withLock { $0 += 1 }
      }
    )

    notifyingServer.start { fd, _ in
      notifyingServer.addSubscriber((), for: fd)
      _ = notifyingServer.send(TestMessage(kind: "subscribed"), to: fd)
      return .keepOpen
    }
    defer { notifyingServer.stop() }

    let response: TestMessage = try LineSocketClientTransport<TestRequest, TestMessage>(
      socketPath: socketPath
    ).send(request: TestRequest(command: "subscribe"))

    XCTAssertEqual(response, TestMessage(kind: "subscribed"))

    try await waitUntil("subscriber removal callback") {
      removedSubscribers.withLock { $0 == 1 }
    }
  }

  func testSubscriberRegistrationFailsAfterTransportStops() throws {
    let logger = Self.makeLogger()
    let server = makeServer(logger: logger)

    XCTAssertTrue(server.start { _, _ in .close })
    server.stop()

    XCTAssertFalse(server.addSubscriber((), for: 42))
    XCTAssertTrue(server.subscribersSnapshot().isEmpty)
  }

  func testSubscriberRegistrationReplacesExistingSubscription() async throws {
    let logger = Self.makeLogger()
    let server = LineSocketServerTransport<String, TestRequest, TestMessage>(
      socketPath: socketPath,
      serverLabel: "test agent",
      logger: logger
    )

    XCTAssertTrue(
      server.start { fd, request in
        guard server.addSubscriber(request.command, for: fd) else { return .close }
        _ = server.send(TestMessage(kind: request.command), to: fd)
        return .keepOpen
      })
    defer { server.stop() }

    let clientFD = try connectUnixSocket()
    defer { close(clientFD) }

    try writeLine(#"{"command":"initial"}"#, to: clientFD)
    XCTAssertEqual(try readMessage(from: clientFD), TestMessage(kind: "initial"))
    try writeLine(#"{"command":"refreshed"}"#, to: clientFD)
    XCTAssertEqual(try readMessage(from: clientFD), TestMessage(kind: "refreshed"))

    try await waitUntil("subscriber replacement") {
      server.subscribersSnapshot().map(\.subscriber) == ["refreshed"]
    }
  }

  func testServerStopWakesIdleClientReadTask() async throws {
    let logger = Self.makeLogger()
    let server = makeServer(logger: logger)

    XCTAssertTrue(
      server.start { _, _ in
        XCTFail("idle client should not dispatch a request")
        return .close
      })
    defer { server.stop() }

    let clientFD = try connectUnixSocket()
    defer { close(clientFD) }

    server.stop()

    try await waitUntil("idle client socket to be closed") {
      self.socketIsClosed(clientFD)
    }
  }

  func testServerClosesClientThatDoesNotSendInitialRequest() async throws {
    let logger = Self.makeLogger()
    let server = LineSocketServerTransport<Void, TestRequest, TestMessage>(
      socketPath: socketPath,
      serverLabel: "test agent",
      logger: logger,
      initialRequestTimeout: 0.05
    )

    server.start { _, _ in
      XCTFail("idle client should not dispatch a request")
      return .close
    }
    defer { server.stop() }

    let clientFD = try connectUnixSocket()
    defer { close(clientFD) }

    try await waitUntil("idle client socket to time out") {
      self.socketIsClosed(clientFD)
    }
  }

  func testServerClosesClientThatExceedsRequestLimit() async throws {
    let logger = Self.makeLogger()
    let server = LineSocketServerTransport<Void, TestRequest, TestMessage>(
      socketPath: socketPath,
      serverLabel: "test agent",
      logger: logger,
      maxRequestBytes: 16
    )

    server.start { _, _ in
      XCTFail("oversized request should not be dispatched")
      return .close
    }
    defer { server.stop() }

    let clientFD = try connectUnixSocket()
    defer { close(clientFD) }
    try writeLine(#"{"command":"request-that-is-too-large"}"#, to: clientFD)

    try await waitUntil("oversized request socket to close") {
      self.socketIsClosed(clientFD)
    }
  }

  func testServerRejectsClientsAboveConcurrencyLimit() async throws {
    let logger = Self.makeLogger()
    let server = LineSocketServerTransport<Void, TestRequest, TestMessage>(
      socketPath: socketPath,
      serverLabel: "test agent",
      logger: logger,
      initialRequestTimeout: 1,
      maxConcurrentClients: 1
    )
    server.start { _, _ in .close }
    defer { server.stop() }

    let firstClientFD = try connectUnixSocket()
    defer { close(firstClientFD) }
    let secondClientFD = try connectUnixSocket()
    defer { close(secondClientFD) }

    try await waitUntil("excess client socket to close") {
      self.socketIsClosed(secondClientFD)
    }
    XCTAssertFalse(socketIsClosed(firstClientFD))
  }

  func testInitialRequestTimeoutDoesNotCloseSubscriber() async throws {
    let logger = Self.makeLogger()
    let server = LineSocketServerTransport<Void, TestRequest, TestMessage>(
      socketPath: socketPath,
      serverLabel: "test agent",
      logger: logger,
      initialRequestTimeout: 0.05
    )

    server.start { fd, _ in
      server.addSubscriber((), for: fd)
      return .keepOpen
    }
    defer { server.stop() }

    let clientFD = try connectUnixSocket()
    defer { close(clientFD) }
    try writeLine(#"{"command":"subscribe"}"#, to: clientFD)

    try await waitUntil("subscriber to stay registered") {
      server.subscribersSnapshot().count == 1
    }
    try await Task.sleep(nanoseconds: 100_000_000)

    XCTAssertEqual(server.subscribersSnapshot().count, 1)
    XCTAssertFalse(socketIsClosed(clientFD))
  }

  func testServerCanRestartOnSameSocketPathAfterStopWithoutClients() async throws {
    let logger = Self.makeLogger()
    let firstServer = makeServer(logger: logger)

    firstServer.start { _, _ in
      XCTFail("server without clients should not dispatch a request")
      return .close
    }

    firstServer.stop()

    try await waitUntil("first server socket to be removed") {
      !FileManager.default.fileExists(atPath: self.socketPath)
    }

    let secondServer = makeServer(logger: logger)
    secondServer.start { fd, _ in
      _ = secondServer.send(TestMessage(kind: "pong"), to: fd)
      return .close
    }
    defer { secondServer.stop() }

    let response: TestMessage = try LineSocketClientTransport<TestRequest, TestMessage>(
      socketPath: socketPath
    ).send(request: TestRequest(command: "ping"))

    XCTAssertEqual(response, TestMessage(kind: "pong"))
  }

  func testConcurrentServerSendsPreserveMessageFraming() async throws {
    let logger = Self.makeLogger()
    let server = makeServer(logger: logger)
    let acceptedFD = LockedState<Int32?>(nil)

    server.start { fd, _ in
      acceptedFD.withLock { $0 = fd }
      return .keepOpen
    }
    defer { server.stop() }

    let clientFD = try connectUnixSocket()
    defer { close(clientFD) }
    try writeLine(#"{"command":"subscribe"}"#, to: clientFD)
    try await waitUntil("server to accept client request") {
      acceptedFD.withLock { $0 != nil }
    }
    let serverFD = try XCTUnwrap(acceptedFD.withLock { $0 })

    let messages = (0..<16).map { index in
      TestMessage(kind: "\(index):" + String(repeating: "payload\(index)", count: 8_000))
    }
    let sendResults = LockedState<[Bool]>([])

    for message in messages {
      DispatchQueue.global().async {
        let sent = server.send(message, to: serverFD)
        sendResults.withLock { $0.append(sent) }
      }
    }

    var received: [TestMessage] = []
    for _ in messages.indices {
      received.append(try readMessage(from: clientFD))
    }

    XCTAssertEqual(sendResults.withLock { $0 }, Array(repeating: true, count: messages.count))
    XCTAssertEqual(Set(received.map(\.kind)), Set(messages.map(\.kind)))
  }

  func testOneShotClientRejectsOversizedResponse() async throws {
    let logger = Self.makeLogger()
    let server = makeServer(logger: logger)
    server.start { fd, _ in
      _ = server.send(TestMessage(kind: String(repeating: "x", count: 64)), to: fd)
      return .close
    }
    defer { server.stop() }

    let client = LineSocketClientTransport<TestRequest, TestMessage>(
      socketPath: socketPath,
      maxResponseBytes: 16
    )
    XCTAssertThrowsError(try client.send(request: TestRequest(command: "ping")))
  }

  func testOneShotClientTimesOutWhileWaitingForResponse() throws {
    let logger = Self.makeLogger()
    let server = makeServer(logger: logger)
    server.start { _, _ in .keepOpen }
    defer { server.stop() }

    let client = LineSocketClientTransport<TestRequest, TestMessage>(
      socketPath: socketPath,
      responseTimeout: 0.02
    )

    XCTAssertThrowsError(try client.send(request: TestRequest(command: "ping"))) { error in
      guard case LineSocketClientTransportError.responseTimedOut = error else {
        return XCTFail("unexpected error: \(error)")
      }
    }
  }

  func testOneShotClientTimesOutWhenPeerDoesNotReadRequest() throws {
    let listener = try makeOwnedListeningUnixSocket(at: socketPath, backlog: 1)
    let listeningFD = listener.fd
    let releaseAcceptedSocket = DispatchSemaphore(value: 0)
    let acceptFinished = DispatchSemaphore(value: 0)

    DispatchQueue.global().async {
      let acceptedFD = accept(listeningFD, nil, nil)
      if acceptedFD >= 0 {
        var receiveBufferSize: Int32 = 1_024
        _ = setsockopt(
          acceptedFD,
          SOL_SOCKET,
          SO_RCVBUF,
          &receiveBufferSize,
          socklen_t(MemoryLayout<Int32>.size)
        )
        _ = releaseAcceptedSocket.wait(timeout: .now() + 2)
        close(acceptedFD)
      }
      acceptFinished.signal()
    }

    defer {
      releaseAcceptedSocket.signal()
      closeListeningUnixSocket(listener)
      _ = acceptFinished.wait(timeout: .now() + 2)
    }

    let client = LineSocketClientTransport<TestRequest, TestMessage>(
      socketPath: socketPath,
      responseTimeout: 0.05
    )
    let oversizedRequest = TestRequest(command: String(repeating: "x", count: 16 * 1_024 * 1_024))
    let start = Date()

    XCTAssertThrowsError(try client.send(request: oversizedRequest)) { error in
      guard case LineSocketClientTransportError.writeTimedOut = error else {
        return XCTFail("unexpected error: \(error)")
      }
    }

    XCTAssertLessThan(Date().timeIntervalSince(start), 2)
  }

  func testRapidServerRestartsKeepAcceptLoopBoundToCurrentRun() async throws {
    let logger = Self.makeLogger()
    let server = makeServer(logger: logger)
    defer { server.stop() }

    for iteration in 0..<25 {
      server.start { fd, request in
        _ = server.send(TestMessage(kind: "\(iteration):\(request.command)"), to: fd)
        return .close
      }

      let response: TestMessage = try LineSocketClientTransport<TestRequest, TestMessage>(
        socketPath: socketPath
      ).send(request: TestRequest(command: "ping"))
      XCTAssertEqual(response, TestMessage(kind: "\(iteration):ping"))

      server.stop()
    }
  }

  private func makeServer(logger: ProcessLogger)
    -> LineSocketServerTransport<Void, TestRequest, TestMessage>
  {
    LineSocketServerTransport(
      socketPath: socketPath,
      serverLabel: "test agent",
      logger: logger
    )
  }

  private func waitUntil(
    _ description: String,
    timeoutNanoseconds: UInt64 = 1_000_000_000,
    condition: @escaping () -> Bool
  ) async throws {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds

    while DispatchTime.now().uptimeNanoseconds < deadline {
      if condition() {
        return
      }

      try await Task.sleep(nanoseconds: 10_000_000)
    }

    XCTFail("Timed out waiting for \(description)")
  }

  private func connectUnixSocket() throws -> Int32 {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    XCTAssertGreaterThanOrEqual(fd, 0)

    guard fd >= 0 else {
      throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }

    var address = try makeSockAddrUn(path: socketPath)
    let addressLength = socklen_t(MemoryLayout<sockaddr_un>.size)
    let result = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        connect(fd, $0, addressLength)
      }
    }

    guard result == 0 else {
      let error = NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
      close(fd)
      throw error
    }

    return fd
  }

  private func writeLine(_ line: String, to fd: Int32) throws {
    let payload = Data((line + "\n").utf8)

    try payload.withUnsafeBytes { rawBuffer in
      guard let baseAddress = rawBuffer.baseAddress else { return }

      var sent = 0
      while sent < payload.count {
        let count = write(fd, baseAddress.advanced(by: sent), payload.count - sent)

        if count > 0 {
          sent += count
          continue
        }

        if count < 0, errno == EINTR {
          continue
        }

        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
      }
    }
  }

  private func readMessage(from fd: Int32) throws -> TestMessage {
    let line = try readLine(from: fd)
    return try JSONDecoder().decode(TestMessage.self, from: Data(line.utf8))
  }

  private func readLine(from fd: Int32) throws -> String {
    var bytes: [UInt8] = []
    var byte = UInt8(0)

    while true {
      var pollFD = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
      let pollResult = poll(&pollFD, 1, 1_000)

      if pollResult == 0 {
        throw NSError(
          domain: NSPOSIXErrorDomain,
          code: Int(ETIMEDOUT),
          userInfo: [NSLocalizedDescriptionKey: "timed out waiting for socket line"]
        )
      }

      if pollResult < 0 {
        if errno == EINTR {
          continue
        }

        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
      }

      if (pollFD.revents & Int16(POLLIN)) == 0 {
        throw NSError(
          domain: NSPOSIXErrorDomain,
          code: 0,
          userInfo: [NSLocalizedDescriptionKey: "socket closed before newline"]
        )
      }

      let count = read(fd, &byte, 1)

      if count > 0 {
        if byte == 0x0A {
          return String(decoding: bytes, as: UTF8.self)
        }

        bytes.append(byte)
        continue
      }

      if count == 0 {
        throw NSError(
          domain: NSPOSIXErrorDomain,
          code: 0,
          userInfo: [NSLocalizedDescriptionKey: "socket closed before newline"]
        )
      }

      if errno == EINTR {
        continue
      }

      throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
  }

  private func socketIsClosed(_ fd: Int32) -> Bool {
    var buffer = [UInt8](repeating: 0, count: 1)
    let result = recv(fd, &buffer, buffer.count, MSG_DONTWAIT)

    if result == 0 {
      return true
    }

    if result < 0 {
      return errno != EAGAIN && errno != EWOULDBLOCK
    }

    return false
  }

  private static func makeLogger() -> ProcessLogger {
    ProcessLogger(
      label: "easybar.shared.agent-socket-client.tests",
      minimumLevel: .error,
      outputStream: nil,
      errorStream: nil
    )
  }
}
