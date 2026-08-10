import Darwin
import Dispatch
import Foundation

private let defaultSocketWriteTimeout: TimeInterval = 1

/// Errors produced while opening a Unix-domain client socket.
public enum UnixSocketConnectError: Error, CustomStringConvertible, LocalizedError {
  case createSocket(errnoValue: Int32)
  case configureNoSigPipe
  case configureBlockingMode(errnoValue: Int32)
  case invalidAddress(any Error)
  case connect(errnoValue: Int32)
  case timedOut(TimeInterval)

  public var description: String {
    switch self {
    case .createSocket(let errnoValue):
      return "socket creation failed: \(Self.errnoDescription(errnoValue))"
    case .configureNoSigPipe:
      return "failed to configure socket no-sigpipe"
    case .configureBlockingMode(let errnoValue):
      return "failed to configure socket blocking mode: \(Self.errnoDescription(errnoValue))"
    case .invalidAddress(let error):
      return "invalid Unix socket address: \(error)"
    case .connect(let errnoValue):
      return "socket connection failed: \(Self.errnoDescription(errnoValue))"
    case .timedOut(let timeout):
      return "socket connection timed out after \(timeout) seconds"
    }
  }

  public var errorDescription: String? { description }

  private static func errnoDescription(_ value: Int32) -> String {
    "\(String(cString: strerror(value))) (errno \(value))"
  }
}

/// Describes a failed deadline-bound socket write.
public enum UnixSocketWriteError: Error, Equatable, Sendable {
  case closed
  case timedOut
  case failed(errnoValue: Int32)
}

/// Identifies one concrete filesystem entry used by a Unix-domain socket.
public struct UnixSocketPathIdentity: Equatable, Sendable {
  public let device: UInt64
  public let inode: UInt64

  fileprivate init(_ value: stat) {
    device = UInt64(value.st_dev)
    inode = UInt64(value.st_ino)
  }
}

/// Owns a listening descriptor together with the exact socket path it created.
public struct OwnedUnixSocketListener: Sendable {
  public let fd: Int32
  public let socketPath: String
  public let pathIdentity: UnixSocketPathIdentity

  fileprivate init(fd: Int32, socketPath: String, pathIdentity: UnixSocketPathIdentity) {
    self.fd = fd
    self.socketPath = socketPath
    self.pathIdentity = pathIdentity
  }
}

/// Returns a finite positive timeout and rejects NaN and infinity consistently.
public func normalizedSocketTimeout(
  _ value: TimeInterval,
  fallback: TimeInterval = 5,
  minimum: TimeInterval = 0.001
) -> TimeInterval {
  let finiteFallback = fallback.isFinite && fallback > 0 ? fallback : 5
  let finiteMinimum = minimum.isFinite && minimum > 0 ? minimum : 0.001
  guard value.isFinite else { return max(finiteMinimum, finiteFallback) }
  return max(finiteMinimum, value)
}

/// Creates and connects one Unix-domain client socket.
public func openConnectedUnixSocket(
  at socketPath: String,
  timeout: TimeInterval = 5,
  keepNonBlocking: Bool = false
) throws -> Int32 {
  let normalizedTimeout = normalizedSocketTimeout(timeout)
  return try openConnectedUnixSocket(
    at: socketPath,
    timeout: normalizedTimeout,
    deadline: monotonicPollDeadline(after: normalizedTimeout),
    restoreBlocking: !keepNonBlocking
  )
}

/// Creates and connects one Unix-domain client socket against an existing deadline.
func openConnectedUnixSocket(
  at socketPath: String,
  timeout: TimeInterval,
  deadline: UInt64,
  restoreBlocking: Bool
) throws -> Int32 {
  let fd = socket(AF_UNIX, SOCK_STREAM, 0)
  guard fd >= 0 else {
    throw UnixSocketConnectError.createSocket(errnoValue: errno)
  }

  do {
    guard configureNoSigPipe(fd: fd) else {
      throw UnixSocketConnectError.configureNoSigPipe
    }

    var address: sockaddr_un
    do {
      address = try makeSockAddrUn(path: socketPath)
    } catch {
      throw UnixSocketConnectError.invalidAddress(error)
    }

    let addressLength = socklen_t(MemoryLayout<sockaddr_un>.size)
    let originalFlags = fcntl(fd, F_GETFL)
    guard originalFlags >= 0, fcntl(fd, F_SETFL, originalFlags | O_NONBLOCK) == 0 else {
      throw UnixSocketConnectError.configureBlockingMode(errnoValue: errno)
    }

    let result = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.connect(fd, $0, addressLength)
      }
    }
    if result != 0 {
      guard errno == EINPROGRESS else {
        throw UnixSocketConnectError.connect(errnoValue: errno)
      }

      var descriptor = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
      var pollResult: Int32
      repeat {
        pollResult = poll(&descriptor, 1, remainingPollMilliseconds(until: deadline))
      } while pollResult < 0 && errno == EINTR
      guard pollResult > 0 else {
        if pollResult == 0 { throw UnixSocketConnectError.timedOut(timeout) }
        throw UnixSocketConnectError.connect(errnoValue: errno)
      }

      var socketError: Int32 = 0
      var errorLength = socklen_t(MemoryLayout<Int32>.size)
      guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &socketError, &errorLength) == 0 else {
        throw UnixSocketConnectError.connect(errnoValue: errno)
      }
      guard socketError == 0 else {
        throw UnixSocketConnectError.connect(errnoValue: socketError)
      }
    }

    if restoreBlocking, fcntl(fd, F_SETFL, originalFlags) != 0 {
      throw UnixSocketConnectError.configureBlockingMode(errnoValue: errno)
    }

    return fd
  } catch {
    close(fd)
    throw error
  }
}

/// Returns a monotonic deadline suitable for retrying interrupted `poll` calls.
func monotonicPollDeadline(after timeout: TimeInterval) -> UInt64 {
  let normalizedTimeout = normalizedSocketTimeout(timeout)
  let milliseconds = UInt64(min(normalizedTimeout * 1_000, Double(Int32.max)))
  let now = DispatchTime.now().uptimeNanoseconds
  let (deadline, overflow) = now.addingReportingOverflow(milliseconds * 1_000_000)
  return overflow ? UInt64.max : deadline
}

/// Returns the remaining whole-millisecond timeout for a monotonic deadline.
func remainingPollMilliseconds(until deadline: UInt64) -> Int32 {
  let now = DispatchTime.now().uptimeNanoseconds
  guard deadline > now else { return 0 }

  let remainingNanoseconds = deadline - now
  let wholeMilliseconds = remainingNanoseconds / 1_000_000
  let roundedUpMilliseconds = wholeMilliseconds + (remainingNanoseconds % 1_000_000 == 0 ? 0 : 1)
  return Int32(min(roundedUpMilliseconds, UInt64(Int32.max)))
}

/// Errors produced while preparing Unix-domain server sockets.
public enum UnixSocketListenError: Error, CustomStringConvertible, LocalizedError {
  case createDirectory(path: String, message: String)
  case createSocket(errnoValue: Int32)
  case configureNoSigPipe(fd: Int32)
  case invalidAddress(path: String, message: String)
  case existingPathIsNotSocket(path: String)
  case existingSocketIsActive(path: String)
  case inspectPath(path: String, errnoValue: Int32)
  case bind(path: String, errnoValue: Int32)
  case chmod(path: String, errnoValue: Int32)
  case listen(path: String, errnoValue: Int32)

  /// Printable socket setup error.
  public var description: String {
    switch self {
    case .createDirectory(let path, let message):
      return "failed to create socket directory path=\(path) error=\(message)"
    case .createSocket(let errnoValue):
      return "failed to create socket errno=\(errnoValue)"
    case .configureNoSigPipe(let fd):
      return "failed to configure server socket no-sigpipe fd=\(fd)"
    case .invalidAddress(let path, let message):
      return "invalid socket path path=\(path) error=\(message)"
    case .existingPathIsNotSocket(let path):
      return "socket path already exists and is not a socket path=\(path)"
    case .existingSocketIsActive(let path):
      return "socket path is already owned by an active listener path=\(path)"
    case .inspectPath(let path, let errnoValue):
      return "failed to inspect socket path path=\(path) errno=\(errnoValue)"
    case .bind(let path, let errnoValue):
      return "socket bind failed path=\(path) errno=\(errnoValue)"
    case .chmod(let path, let errnoValue):
      return "socket chmod failed path=\(path) errno=\(errnoValue)"
    case .listen(let path, let errnoValue):
      return "socket listen failed path=\(path) errno=\(errnoValue)"
    }
  }

  /// User-facing socket setup error.
  public var errorDescription: String? { description }
}

/// Configures one Unix socket file descriptor to suppress SIGPIPE on write.
@discardableResult
public func configureNoSigPipe(fd: Int32) -> Bool {
  var value: Int32 = 1
  return setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &value, socklen_t(MemoryLayout<Int32>.size)) == 0
}

/// Configures one file descriptor for nonblocking I/O.
@discardableResult
public func configureNonBlocking(fd: Int32) -> Bool {
  let flags = fcntl(fd, F_GETFL)
  return flags >= 0 && fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0
}

/// Restores one file descriptor to blocking I/O.
@discardableResult
public func configureBlocking(fd: Int32) -> Bool {
  let flags = fcntl(fd, F_GETFL)
  return flags >= 0 && fcntl(fd, F_SETFL, flags & ~O_NONBLOCK) == 0
}

/// Writes the full data payload to one connected Unix socket with a finite default deadline.
public func writeAll(_ data: Data, to fd: Int32) -> Bool {
  writeAll(data, to: fd, timeout: defaultSocketWriteTimeout) == nil
}

/// Writes the full data payload before the supplied timeout expires.
public func writeAll(
  _ data: Data,
  to fd: Int32,
  timeout: TimeInterval
) -> UnixSocketWriteError? {
  writeAll(
    data,
    to: fd,
    deadline: monotonicPollDeadline(after: normalizedSocketTimeout(timeout))
  )
}

/// Writes the full data payload before an existing monotonic deadline expires.
public func writeAll(
  _ data: Data,
  to fd: Int32,
  deadline: UInt64
) -> UnixSocketWriteError? {
  guard !data.isEmpty else { return nil }

  return data.withUnsafeBytes { rawBuffer in
    guard let base = rawBuffer.baseAddress else { return .closed }

    var sent = 0
    while sent < data.count {
      let written = Darwin.write(fd, base.advanced(by: sent), data.count - sent)

      if written > 0 {
        sent += written
        continue
      }

      if written == 0 {
        return .closed
      }

      let errnoValue = errno
      if errnoValue == EINTR {
        continue
      }

      if isTemporarilyUnavailable(errnoValue) {
        switch waitForWritable(fd: fd, deadline: deadline) {
        case .ready:
          continue
        case .timedOut:
          return .timedOut
        case .failed(let waitErrno):
          return .failed(errnoValue: waitErrno)
        }
      }

      if errnoValue == EPIPE || errnoValue == ECONNRESET || errnoValue == EBADF {
        return .closed
      }
      return .failed(errnoValue: errnoValue)
    }

    return nil
  }
}

/// Creates, binds, chmods, and starts one Unix-domain listening socket with path ownership.
public func makeOwnedListeningUnixSocket(
  at socketPath: String,
  backlog: Int32,
  mode: mode_t = 0o600,
  onChmodFailure: ((Int32) -> Void)? = nil
) throws -> OwnedUnixSocketListener {
  let socketURL = URL(fileURLWithPath: socketPath)
  let socketDir = socketURL.deletingLastPathComponent()

  do {
    try FileManager.default.createDirectory(
      at: socketDir,
      withIntermediateDirectories: true
    )
  } catch {
    throw UnixSocketListenError.createDirectory(
      path: socketDir.path,
      message: error.localizedDescription
    )
  }

  try removeStaleSocketIfNeeded(at: socketPath)

  let fd = socket(AF_UNIX, SOCK_STREAM, 0)
  guard fd >= 0 else {
    throw UnixSocketListenError.createSocket(errnoValue: errno)
  }

  var boundIdentity: UnixSocketPathIdentity?
  do {
    guard configureNoSigPipe(fd: fd) else {
      throw UnixSocketListenError.configureNoSigPipe(fd: fd)
    }

    let addr: sockaddr_un
    do {
      addr = try makeSockAddrUn(path: socketPath)
    } catch {
      throw UnixSocketListenError.invalidAddress(path: socketPath, message: "\(error)")
    }

    var mutableAddr = addr
    let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)

    let bindResult = withUnsafePointer(to: &mutableAddr) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        bind(fd, $0, addrLen)
      }
    }

    guard bindResult == 0 else {
      throw UnixSocketListenError.bind(path: socketPath, errnoValue: errno)
    }
    boundIdentity = try unixSocketPathIdentity(at: socketPath)

    if chmod(socketPath, mode) != 0 {
      let errnoValue = errno
      onChmodFailure?(errnoValue)
      throw UnixSocketListenError.chmod(path: socketPath, errnoValue: errnoValue)
    }

    guard listen(fd, backlog) == 0 else {
      throw UnixSocketListenError.listen(path: socketPath, errnoValue: errno)
    }

    guard let boundIdentity else {
      throw UnixSocketListenError.inspectPath(path: socketPath, errnoValue: ENOENT)
    }
    return OwnedUnixSocketListener(
      fd: fd,
      socketPath: socketPath,
      pathIdentity: boundIdentity
    )
  } catch {
    close(fd)
    if let boundIdentity {
      unlinkSocketPathIfOwned(socketPath, expectedIdentity: boundIdentity)
    }
    throw error
  }
}

/// Closes one owned listener and removes only the path entry it originally created.
public func closeListeningUnixSocket(_ listener: OwnedUnixSocketListener) {
  Darwin.shutdown(listener.fd, SHUT_RDWR)
  close(listener.fd)
  unlinkSocketPathIfOwned(listener.socketPath, expectedIdentity: listener.pathIdentity)
}

/// Returns the identity of one filesystem socket entry.
public func unixSocketPathIdentity(at socketPath: String) throws -> UnixSocketPathIdentity {
  var value = stat()
  guard lstat(socketPath, &value) == 0 else {
    throw UnixSocketListenError.inspectPath(path: socketPath, errnoValue: errno)
  }
  guard value.st_mode & S_IFMT == S_IFSOCK else {
    throw UnixSocketListenError.existingPathIsNotSocket(path: socketPath)
  }
  return UnixSocketPathIdentity(value)
}

/// Removes a socket path only when it still refers to the expected filesystem entry.
@discardableResult
public func unlinkSocketPathIfOwned(
  _ socketPath: String,
  expectedIdentity: UnixSocketPathIdentity
) -> Bool {
  guard let currentIdentity = try? unixSocketPathIdentity(at: socketPath) else { return false }
  guard currentIdentity == expectedIdentity else { return false }
  return unlink(socketPath) == 0
}

private enum SocketPollResult {
  case ready
  case timedOut
  case failed(errnoValue: Int32)
}

/// Removes a refused stale socket but never unlinks a live or ambiguous listener.
private func removeStaleSocketIfNeeded(at socketPath: String) throws {
  var existingInfo = stat()
  if lstat(socketPath, &existingInfo) != 0 {
    if errno == ENOENT { return }
    throw UnixSocketListenError.inspectPath(path: socketPath, errnoValue: errno)
  }

  guard existingInfo.st_mode & S_IFMT == S_IFSOCK else {
    throw UnixSocketListenError.existingPathIsNotSocket(path: socketPath)
  }

  do {
    let probeFD = try openConnectedUnixSocket(at: socketPath, timeout: 0.1, keepNonBlocking: true)
    close(probeFD)
    throw UnixSocketListenError.existingSocketIsActive(path: socketPath)
  } catch let error as UnixSocketListenError {
    throw error
  } catch let error as UnixSocketConnectError {
    switch error {
    case .connect(let errnoValue) where errnoValue == ECONNREFUSED || errnoValue == ENOENT:
      break
    default:
      throw UnixSocketListenError.existingSocketIsActive(path: socketPath)
    }
  } catch {
    throw UnixSocketListenError.existingSocketIsActive(path: socketPath)
  }

  let expectedIdentity = UnixSocketPathIdentity(existingInfo)
  guard unlinkSocketPathIfOwned(socketPath, expectedIdentity: expectedIdentity) else {
    throw UnixSocketListenError.bind(path: socketPath, errnoValue: errno)
  }
}

/// Returns whether one socket write failed because the descriptor would block.
private func isTemporarilyUnavailable(_ errnoValue: Int32) -> Bool {
  errnoValue == EAGAIN || errnoValue == EWOULDBLOCK
}

/// Waits until one socket fd is writable or the absolute deadline expires.
private func waitForWritable(fd: Int32, deadline: UInt64) -> SocketPollResult {
  var pollDescriptor = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)

  while true {
    let remaining = remainingPollMilliseconds(until: deadline)
    guard remaining > 0 else { return .timedOut }
    let result = poll(&pollDescriptor, 1, remaining)

    if result > 0 {
      let revents = Int32(pollDescriptor.revents)
      if (revents & (POLLERR | POLLHUP | POLLNVAL)) != 0 {
        return .failed(errnoValue: EPIPE)
      }
      if (revents & POLLOUT) != 0 {
        return .ready
      }
      continue
    }

    if result == 0 {
      return .timedOut
    }

    if errno == EINTR {
      continue
    }

    return .failed(errnoValue: errno)
  }
}
