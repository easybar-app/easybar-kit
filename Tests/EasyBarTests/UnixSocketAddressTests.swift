import Darwin
import EasyBarShared
import XCTest

final class UnixSocketAddressTests: XCTestCase {
  func testConnectErrorsProvideActionableDescriptions() {
    XCTAssertEqual(
      UnixSocketConnectError.configureNoSigPipe.description,
      "failed to configure socket no-sigpipe"
    )
    XCTAssertTrue(
      UnixSocketConnectError.connect(errnoValue: ECONNREFUSED).description.contains(
        "errno \(ECONNREFUSED)"
      )
    )
  }

  func testOpenConnectedUnixSocketConnectsToListener() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let path = directory.appendingPathComponent("listener.sock").path
    let listener = try makeOwnedListeningUnixSocket(at: path, backlog: 1)
    defer { closeListeningUnixSocket(listener) }

    let client = try openConnectedUnixSocket(at: path, timeout: 0.1)
    close(client)
  }

  func testOpenConnectedUnixSocketReportsRefusedConnection() {
    let path = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathComponent("missing.sock").path

    XCTAssertThrowsError(try openConnectedUnixSocket(at: path, timeout: 0.1)) { error in
      guard case UnixSocketConnectError.connect = error else {
        return XCTFail("Expected connect error, got \(error)")
      }
    }
  }

  func testConnectTimeoutDescriptionIdentifiesConnectionPhase() {
    XCTAssertEqual(
      UnixSocketConnectError.timedOut(0.25).description,
      "socket connection timed out after 0.25 seconds"
    )
  }

  func testListenChmodErrorsProvideActionableDescriptions() {
    XCTAssertEqual(
      UnixSocketListenError.chmod(path: "/tmp/easybar.sock", errnoValue: EACCES).description,
      "socket chmod failed path=/tmp/easybar.sock errno=\(EACCES)"
    )
  }

  private var temporaryDirectory: URL?

  override func tearDownWithError() throws {
    if let temporaryDirectory {
      try? FileManager.default.removeItem(at: temporaryDirectory)
    }
    try super.tearDownWithError()
  }

  func testMakeSockAddrUnAcceptsMaximumLengthPath() throws {
    let maxPathBytes = MemoryLayout.size(ofValue: sockaddr_un().sun_path) - 1
    let path = "/" + String(repeating: "a", count: maxPathBytes - 1)

    XCTAssertNoThrow(try makeSockAddrUn(path: path))
  }

  func testMakeSockAddrUnRejectsOverlongPath() {
    let maxPathBytes = MemoryLayout.size(ofValue: sockaddr_un().sun_path) - 1
    let path = "/" + String(repeating: "a", count: maxPathBytes)

    XCTAssertThrowsError(try makeSockAddrUn(path: path)) { error in
      guard case UnixSocketAddressError.pathTooLong(let rejectedPath, let rejectedMaxBytes) = error
      else {
        return XCTFail("Expected pathTooLong, got \(error)")
      }

      XCTAssertEqual(rejectedPath, path)
      XCTAssertEqual(rejectedMaxBytes, maxPathBytes)
    }
  }

  func testMakeListeningUnixSocketReplacesStalePathAndAppliesPrivateMode() throws {
    let directory = URL(fileURLWithPath: "/tmp", isDirectory: true)
      .appendingPathComponent("eb-\(UUID().uuidString.prefix(8))", isDirectory: true)
    temporaryDirectory = directory
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let socketPath = directory.appendingPathComponent("server.sock").path
    let staleFD = socket(AF_UNIX, SOCK_STREAM, 0)
    XCTAssertGreaterThanOrEqual(staleFD, 0)
    var staleAddress = try makeSockAddrUn(path: socketPath)
    let staleAddressLength = socklen_t(MemoryLayout<sockaddr_un>.size)
    XCTAssertEqual(
      withUnsafePointer(to: &staleAddress) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
          Darwin.bind(staleFD, $0, staleAddressLength)
        }
      },
      0
    )
    close(staleFD)

    let listener = try makeOwnedListeningUnixSocket(at: socketPath, backlog: 1)
    defer {
      closeListeningUnixSocket(listener)
    }

    var info = stat()
    XCTAssertEqual(lstat(socketPath, &info), 0)
    XCTAssertEqual(info.st_mode & S_IFMT, S_IFSOCK)
    XCTAssertEqual(info.st_mode & 0o777, 0o600)
  }

  func testMakeListeningUnixSocketPreservesExistingRegularFile() throws {
    let directory = URL(fileURLWithPath: "/tmp", isDirectory: true)
      .appendingPathComponent("eb-\(UUID().uuidString.prefix(8))", isDirectory: true)
    temporaryDirectory = directory
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let socketPath = directory.appendingPathComponent("server.sock").path
    try "important data".write(toFile: socketPath, atomically: true, encoding: .utf8)

    XCTAssertThrowsError(try makeOwnedListeningUnixSocket(at: socketPath, backlog: 1)) { error in
      guard case UnixSocketListenError.existingPathIsNotSocket(let path) = error else {
        return XCTFail("Expected existingPathIsNotSocket, got \(error)")
      }
      XCTAssertEqual(path, socketPath)
    }
    XCTAssertEqual(try String(contentsOfFile: socketPath, encoding: .utf8), "important data")
  }
}
