import Darwin
import Foundation
import XCTest

@testable import EasyBarShared

final class SocketTransportHardeningTests: XCTestCase {
  private struct Request: Codable {
    let command: String
  }

  private struct Message: Codable, Equatable {
    let kind: String
  }

  private var directoryURL: URL!
  private var socketPath: String!

  override func setUpWithError() throws {
    try super.setUpWithError()
    directoryURL = URL(fileURLWithPath: "/tmp", isDirectory: true)
      .appendingPathComponent("easybar-socket-hardening-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    socketPath = directoryURL.appendingPathComponent("transport.sock").path
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directoryURL)
    socketPath = nil
    directoryURL = nil
    try super.tearDownWithError()
  }

  func testInitialRequestTimeoutDoesNotResetAfterPartialReads() throws {
    let server = makeServer(
      initialRequestTimeout: 0.12,
      maxConcurrentClients: 1
    )
    XCTAssertTrue(
      server.start { fd, _ in
        server.closeAfterSending(Message(kind: "pong"), to: fd)
      }
    )
    defer { server.stop() }

    let slowClientFD = try connect()
    defer { close(slowClientFD) }
    let partialRequest = Data(#"{"command":"unfinished"}"#.utf8)

    for byte in partialRequest.prefix(6) {
      usleep(40_000)
      if writeAll(Data([byte]), to: slowClientFD, timeout: 0.1) != nil {
        break
      }
    }
    usleep(20_000)

    let response: Message = try LineSocketClientTransport<Request, Message>(
      socketPath: socketPath,
      responseTimeout: 1
    ).send(request: Request(command: "ping"))
    XCTAssertEqual(response, Message(kind: "pong"))
  }

  func testSubscriberDoesNotConsumeRequestClientCapacity() async throws {
    let server = makeServer(maxConcurrentClients: 1)
    XCTAssertTrue(
      server.start { fd, request in
        if request.command == "subscribe" {
          XCTAssertTrue(server.addSubscriber((), for: fd))
          XCTAssertTrue(server.send(Message(kind: "subscribed"), to: fd))
          return .keepOpen
        }

        return server.closeAfterSending(Message(kind: "pong"), to: fd)
      }
    )
    defer { server.stop() }

    let subscriberFD = try connect()
    defer { close(subscriberFD) }
    try writeLine(#"{"command":"subscribe"}"#, to: subscriberFD)
    XCTAssertEqual(try readMessage(from: subscriberFD), Message(kind: "subscribed"))

    try await waitUntil { server.subscribersSnapshot().count == 1 }

    let response: Message = try LineSocketClientTransport<Request, Message>(
      socketPath: socketPath,
      responseTimeout: 1
    ).send(request: Request(command: "ping"))
    XCTAssertEqual(response, Message(kind: "pong"))
  }

  func testSecondServerDoesNotUnlinkLiveListener() throws {
    let first = makeServer()
    XCTAssertTrue(
      first.start { fd, _ in
        first.closeAfterSending(Message(kind: "pong"), to: fd)
      }
    )
    defer { first.stop() }

    let second = makeServer()
    XCTAssertFalse(second.start { _, _ in .close })
    defer { second.stop() }

    let response: Message = try LineSocketClientTransport<Request, Message>(
      socketPath: socketPath,
      responseTimeout: 1
    ).send(request: Request(command: "ping"))
    XCTAssertEqual(response, Message(kind: "pong"))
  }

  func testStopDoesNotRemoveReplacementFilesystemEntry() throws {
    let server = makeServer()
    XCTAssertTrue(server.start { _, _ in .close })

    XCTAssertEqual(unlink(socketPath), 0)
    let replacement = Data("replacement".utf8)
    XCTAssertTrue(FileManager.default.createFile(atPath: socketPath, contents: replacement))

    server.stop()

    XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: socketPath)), replacement)
  }

  func testServerStopIsBoundedWhileClientDoesNotReadResponse() throws {
    let handlerEntered = DispatchSemaphore(value: 0)
    let server = makeServer(writeTimeout: 0.1)
    let payload = Message(kind: String(repeating: "x", count: 8 * 1024 * 1024))

    XCTAssertTrue(
      server.start { fd, _ in
        handlerEntered.signal()
        _ = server.send(payload, to: fd)
        return .close
      }
    )

    let clientFD = try connect()
    defer { close(clientFD) }
    var receiveBufferSize: Int32 = 1024
    _ = setsockopt(
      clientFD,
      SOL_SOCKET,
      SO_RCVBUF,
      &receiveBufferSize,
      socklen_t(MemoryLayout<Int32>.size)
    )
    try writeLine(#"{"command":"large"}"#, to: clientFD)
    XCTAssertEqual(handlerEntered.wait(timeout: .now() + 1), .success)

    let startedAt = Date()
    server.stop()
    XCTAssertLessThan(Date().timeIntervalSince(startedAt), 1)
  }

  func testAgentStopDoesNotWaitForStalledSubscribeWrite() throws {
    let listener = try makeOwnedListeningUnixSocket(at: socketPath, backlog: 1)
    let accepted = DispatchSemaphore(value: 0)
    let releasePeer = DispatchSemaphore(value: 0)
    let peerFinished = DispatchSemaphore(value: 0)

    DispatchQueue.global().async {
      let fd = accept(listener.fd, nil, nil)
      if fd >= 0 {
        var receiveBufferSize: Int32 = 1024
        _ = setsockopt(
          fd,
          SOL_SOCKET,
          SO_RCVBUF,
          &receiveBufferSize,
          socklen_t(MemoryLayout<Int32>.size)
        )
        accepted.signal()
        _ = releasePeer.wait(timeout: .now() + 3)
        close(fd)
      }
      peerFinished.signal()
    }

    defer {
      releasePeer.signal()
      closeListeningUnixSocket(listener)
      _ = peerFinished.wait(timeout: .now() + 3)
    }

    let connected = DispatchSemaphore(value: 0)
    let client = AgentSocketClient<Request, Message>(
      label: "stalled test agent",
      socketPath: { self.socketPath },
      subscribeRequest: {
        Request(command: String(repeating: "x", count: 8 * 1024 * 1024))
      },
      handleMessage: { _, _ in },
      clearState: { _ in },
      onConnected: { connected.signal() },
      writeTimeout: 1,
      logger: Self.makeLogger()
    )

    client.start()
    XCTAssertEqual(accepted.wait(timeout: .now() + 1), .success)
    XCTAssertEqual(connected.wait(timeout: .now() + 1), .success)
    usleep(20_000)

    let startedAt = Date()
    client.stop()
    XCTAssertLessThan(Date().timeIntervalSince(startedAt), 0.5)
  }

  func testNonFiniteTimeoutsUseFiniteFallbacks() {
    XCTAssertEqual(normalizedSocketTimeout(.nan), 5)
    XCTAssertEqual(normalizedSocketTimeout(.infinity), 5)
    XCTAssertEqual(normalizedSocketTimeout(-.infinity), 5)
    XCTAssertEqual(normalizedSocketTimeout(0), 0.001)
  }

  private func makeServer(
    initialRequestTimeout: TimeInterval = 5,
    maxConcurrentClients: Int = 32,
    writeTimeout: TimeInterval = 1
  ) -> LineSocketServerTransport<Void, Request, Message> {
    LineSocketServerTransport(
      socketPath: socketPath,
      serverLabel: "socket hardening test",
      logger: Self.makeLogger(),
      initialRequestTimeout: initialRequestTimeout,
      maxConcurrentClients: maxConcurrentClients,
      workerDrainTimeout: 0.5,
      writeTimeout: writeTimeout
    )
  }

  private func connect() throws -> Int32 {
    try openConnectedUnixSocket(at: socketPath, timeout: 1)
  }

  private func writeLine(_ line: String, to fd: Int32) throws {
    let data = Data((line + "\n").utf8)
    guard writeAll(data, to: fd) else {
      throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
  }

  private func readMessage(from fd: Int32) throws -> Message {
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

    return try JSONDecoder().decode(Message.self, from: Data(bytes))
  }

  private func waitUntil(
    timeoutNanoseconds: UInt64 = 1_000_000_000,
    _ condition: @escaping () -> Bool
  ) async throws {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
    while DispatchTime.now().uptimeNanoseconds < deadline {
      if condition() { return }
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTFail("timed out waiting for condition")
  }

  private static func makeLogger() -> ProcessLogger {
    ProcessLogger(label: "socket-hardening-tests", minimumLevel: .error)
  }
}
