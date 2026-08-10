import Darwin
import EasyBarShared
import Foundation
import XCTest

@testable import EasyBarKit

final class LuaTransportAuthenticationTests: XCTestCase {
  func testRejectsWrongTokenBeforeDeliveringRuntimeLines() async throws {
    let directory = Self.shortTemporaryDirectory(prefix: "easybar-lua-auth")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let socketPath = directory.appendingPathComponent("lua.sock").path
    let logger = ProcessLogger(label: "lua-auth-tests", minimumLevel: .error)
    let transport = LuaTransport(logger: logger)
    let delivered = expectation(description: "authenticated line delivered")
    delivered.expectedFulfillmentCount = 1
    let received = LockedState<[String]>([])
    let errorPipe = Pipe()

    try transport.startListening(
      socketPath: socketPath,
      authenticationToken: "correct-token",
      error: errorPipe
    ) { line in
      received.withLock { $0.append(line) }
      delivered.fulfill()
    }
    defer { transport.shutdown() }

    let wrongFD = try openConnectedUnixSocket(at: socketPath, timeout: 1)
    defer { close(wrongFD) }
    XCTAssertTrue(
      writeAll(
        Data("{\"type\":\"hello\",\"token\":\"wrong-token\"}\nunauthorized\n".utf8),
        to: wrongFD
      )
    )

    try await Task.sleep(nanoseconds: 50_000_000)
    XCTAssertTrue(received.withLock { $0.isEmpty })

    let correctFD = try openConnectedUnixSocket(at: socketPath, timeout: 1)
    defer { close(correctFD) }
    XCTAssertTrue(
      writeAll(
        Data("{\"type\":\"hello\",\"token\":\"correct-token\"}\nauthorized\n".utf8),
        to: correctFD
      )
    )

    await fulfillment(of: [delivered], timeout: 1)
    XCTAssertEqual(received.withLock { $0 }, ["authorized"])
  }

  func testShutdownDoesNotWaitForStalledOutboundWriter() async throws {
    let directory = Self.shortTemporaryDirectory(prefix: "easybar-lua-stalled")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let socketPath = directory.appendingPathComponent("lua.sock").path
    let transport = LuaTransport(
      logger: ProcessLogger(label: "lua-stalled-tests", minimumLevel: .error)
    )
    try transport.startListening(
      socketPath: socketPath,
      authenticationToken: "token",
      error: Pipe()
    ) { _ in }

    let clientFD = try openConnectedUnixSocket(at: socketPath, timeout: 1)
    defer { close(clientFD) }
    var receiveBufferSize: Int32 = 1024
    _ = setsockopt(
      clientFD,
      SOL_SOCKET,
      SO_RCVBUF,
      &receiveBufferSize,
      socklen_t(MemoryLayout<Int32>.size)
    )
    XCTAssertTrue(
      writeAll(Data("{\"type\":\"hello\",\"token\":\"token\"}\n".utf8), to: clientFD)
    )
    try await Task.sleep(nanoseconds: 50_000_000)

    let payload = String(repeating: "x", count: 256 * 1024)
    for _ in 0..<32 {
      transport.send(payload)
    }

    let startedAt = Date()
    transport.shutdown()
    XCTAssertLessThan(Date().timeIntervalSince(startedAt), 0.5)
  }

  func testShutdownLeavesReplacementSocketPathUntouched() throws {
    let directory = Self.shortTemporaryDirectory(prefix: "easybar-lua-owner")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let socketPath = directory.appendingPathComponent("lua.sock").path
    let transport = LuaTransport(
      logger: ProcessLogger(label: "lua-owner-tests", minimumLevel: .error)
    )
    try transport.startListening(
      socketPath: socketPath,
      authenticationToken: "token",
      error: Pipe()
    ) { _ in }

    XCTAssertEqual(unlink(socketPath), 0)
    let replacement = Data("replacement".utf8)
    XCTAssertTrue(FileManager.default.createFile(atPath: socketPath, contents: replacement))

    transport.shutdown()
    XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: socketPath)), replacement)
  }

  private static func shortTemporaryDirectory(prefix: String) -> URL {
    URL(fileURLWithPath: "/tmp", isDirectory: true)
      .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
  }
}
