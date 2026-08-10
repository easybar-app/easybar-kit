import Darwin
import Dispatch
import EasyBarShared
import Foundation

/// Opens AeroSpace's native Unix socket subscription without spawning its CLI client.
final class AeroSpaceSocketSubscriptionLauncher: AeroSpaceSubscriptionLaunching,
  @unchecked Sendable
{
  private let socketPath: String
  private let startupTimeout: TimeInterval

  init(
    socketPath: String = "/tmp/bobko.aerospace-\(NSUserName()).sock",
    startupTimeout: TimeInterval = 3
  ) {
    self.socketPath = socketPath
    self.startupTimeout = normalizedSocketTimeout(startupTimeout, fallback: 3)
  }

  func makeSubscription() -> AeroSpaceSubscriptionSession {
    AeroSpaceSocketSubscriptionSession(
      socketPath: socketPath,
      startupTimeout: startupTimeout
    )
  }
}

private final class AeroSpaceSocketSubscriptionSession: AeroSpaceSubscriptionSession,
  @unchecked Sendable
{
  private static let protocolVersion: UInt32 = 1

  private struct State {
    var fd: Int32 = -1
    var stopped = false
  }

  private struct Request: Encodable {
    let args: [String]
    let stdin = ""
    let windowId: UInt32? = nil
    let workspace: String? = nil
  }

  private let socketPath: String
  private let startupTimeout: TimeInterval
  private let state = LockedState(State())

  init(socketPath: String, startupTimeout: TimeInterval) {
    self.socketPath = socketPath
    self.startupTimeout = startupTimeout
  }

  func start(
    onEventFrame: @escaping @Sendable (Data) -> Void,
    onDisconnect: @escaping @Sendable (AeroSpaceSubscriptionSession, String?) -> Void
  ) throws {
    guard !state.withLock(\.stopped) else { return }

    let deadline = startupDeadline(after: startupTimeout)
    let fd = try openConnectedUnixSocket(
      at: socketPath,
      timeout: startupTimeout,
      keepNonBlocking: true
    )

    let accepted = state.withLock { state -> Bool in
      guard !state.stopped else { return false }
      state.fd = fd
      return true
    }
    guard accepted else {
      Darwin.close(fd)
      return
    }

    do {
      try performHandshake(fd: fd, deadline: deadline)
      try sendSubscriptionRequest(fd: fd, deadline: deadline)
      guard configureBlocking(fd: fd) else {
        throw SocketError("failed to restore blocking AeroSpace socket I/O")
      }
    } catch {
      finish(fd: fd)
      throw error
    }

    DetachedTask.run(priority: .utility) { [weak self] in
      guard let self else { return }
      let errorMessage = self.readEvents(fd: fd, onEventFrame: onEventFrame)
      self.finish(fd: fd)
      onDisconnect(self, errorMessage)
    }
  }

  func stop() {
    closeSocket(markStopped: true)
  }

  func invalidate() {
    closeSocket(markStopped: true)
  }

  private func performHandshake(fd: Int32, deadline: UInt64) throws {
    try writeUInt32(Self.protocolVersion, to: fd, deadline: deadline)
    let serverVersion = try readUInt32(from: fd, deadline: deadline)
    guard serverVersion == Self.protocolVersion else {
      throw SocketError("unsupported AeroSpace socket protocol \(serverVersion)")
    }
  }

  private func sendSubscriptionRequest(fd: Int32, deadline: UInt64) throws {
    let payload = try JSONEncoder().encode(
      Request(args: AeroSpaceSubscriptionEvent.subscribeArguments)
    )
    try writeUInt32(UInt32(payload.count), to: fd, deadline: deadline)
    if let error = writeAll(payload, to: fd, deadline: deadline) {
      throw SocketError("failed to write AeroSpace subscription request: \(error)")
    }
  }

  private func readEvents(
    fd: Int32,
    onEventFrame: @escaping @Sendable (Data) -> Void
  ) -> String? {
    do {
      while !state.withLock(\.stopped) {
        let length = try readUInt32(from: fd)
        guard length > 0, length <= 1_048_576 else {
          throw SocketError("invalid AeroSpace event frame length \(length)")
        }
        onEventFrame(try readExactly(Int(length), from: fd))
      }
      return nil
    } catch {
      guard !state.withLock(\.stopped) else { return nil }
      return String(describing: error)
    }
  }

  private func finish(fd: Int32) {
    let shouldClose = state.withLock { state -> Bool in
      guard state.fd == fd else { return false }
      state.fd = -1
      return true
    }
    if shouldClose { Darwin.close(fd) }
  }

  private func closeSocket(markStopped: Bool) {
    let fd = state.withLock { state -> Int32 in
      if markStopped { state.stopped = true }
      let fd = state.fd
      state.fd = -1
      return fd
    }
    guard fd >= 0 else { return }
    _ = shutdown(fd, SHUT_RDWR)
    Darwin.close(fd)
  }

  private func writeUInt32(_ value: UInt32, to fd: Int32, deadline: UInt64) throws {
    var littleEndian = value.littleEndian
    let data = Data(bytes: &littleEndian, count: MemoryLayout<UInt32>.size)
    if let error = writeAll(data, to: fd, deadline: deadline) {
      throw SocketError("AeroSpace socket write failed: \(error)")
    }
  }

  private func readUInt32(from fd: Int32) throws -> UInt32 {
    let data = try readExactly(MemoryLayout<UInt32>.size, from: fd)
    return data.withUnsafeBytes { rawBuffer in
      UInt32(littleEndian: rawBuffer.loadUnaligned(as: UInt32.self))
    }
  }

  private func readUInt32(from fd: Int32, deadline: UInt64) throws -> UInt32 {
    let data = try readExactly(
      MemoryLayout<UInt32>.size,
      from: fd,
      deadline: deadline
    )
    return data.withUnsafeBytes { rawBuffer in
      UInt32(littleEndian: rawBuffer.loadUnaligned(as: UInt32.self))
    }
  }

  private func readExactly(_ count: Int, from fd: Int32) throws -> Data {
    var data = Data(count: count)
    var offset = 0
    while offset < count {
      let readCount = data.withUnsafeMutableBytes { buffer in
        Darwin.read(fd, buffer.baseAddress!.advanced(by: offset), count - offset)
      }
      if readCount > 0 {
        offset += readCount
      } else if readCount == 0 {
        throw SocketError("AeroSpace socket closed")
      } else if errno != EINTR {
        throw SocketError("AeroSpace socket read failed errno=\(errno)")
      }
    }
    return data
  }

  private func readExactly(_ count: Int, from fd: Int32, deadline: UInt64) throws -> Data {
    var data = Data(count: count)
    var offset = 0

    while offset < count {
      let readCount = data.withUnsafeMutableBytes { buffer in
        Darwin.read(fd, buffer.baseAddress!.advanced(by: offset), count - offset)
      }
      if readCount > 0 {
        offset += readCount
        continue
      }
      if readCount == 0 {
        throw SocketError("AeroSpace socket closed during startup")
      }

      let error = errno
      if error == EINTR { continue }
      if error == EAGAIN || error == EWOULDBLOCK {
        try waitForReadable(fd: fd, deadline: deadline)
        continue
      }
      throw SocketError("AeroSpace socket read failed errno=\(error)")
    }

    return data
  }

  private func waitForReadable(fd: Int32, deadline: UInt64) throws {
    let now = DispatchTime.now().uptimeNanoseconds
    guard deadline > now else {
      throw SocketError("AeroSpace socket startup timed out after \(startupTimeout) seconds")
    }

    let remaining = deadline - now
    let milliseconds = min(
      (remaining + 999_999) / 1_000_000,
      UInt64(Int32.max)
    )
    var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
    var result: Int32
    repeat {
      result = poll(&descriptor, 1, Int32(milliseconds))
    } while result < 0 && errno == EINTR

    guard result > 0 else {
      if result == 0 {
        throw SocketError("AeroSpace socket startup timed out after \(startupTimeout) seconds")
      }
      throw SocketError("AeroSpace socket poll failed errno=\(errno)")
    }
  }

  private func startupDeadline(after timeout: TimeInterval) -> UInt64 {
    let nanoseconds = UInt64(min(timeout * 1_000_000_000, Double(UInt64.max)))
    let now = DispatchTime.now().uptimeNanoseconds
    let (deadline, overflow) = now.addingReportingOverflow(nanoseconds)
    return overflow ? UInt64.max : deadline
  }

  private struct SocketError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
  }
}
