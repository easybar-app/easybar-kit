import Darwin
import Foundation

/// Errors produced by the line socket client transport.
public enum LineSocketClientTransportError: Error, CustomStringConvertible {
  case socketFailed
  case connectFailed(UnixSocketConnectError)
  case encodeFailed
  case decodeFailed(String)
  case writeFailed(String)
  case readFailed(String)
  case connectionTimedOut(TimeInterval)
  case writeTimedOut(TimeInterval)
  case responseTimedOut(TimeInterval)
  case noReply

  /// Returns a printable transport error.
  public var description: String {
    switch self {
    case .socketFailed:
      return "socket failed"
    case .connectFailed(let error):
      return "connect failed: \(error.description)"
    case .encodeFailed:
      return "encode failed"
    case .decodeFailed(let message):
      return "decode failed: \(message)"
    case .writeFailed(let message):
      return "write failed: \(message)"
    case .readFailed(let message):
      return "read failed: \(message)"
    case .connectionTimedOut(let timeout):
      return "connection timed out after \(timeout) seconds"
    case .writeTimedOut(let timeout):
      return "request write timed out after \(timeout) seconds"
    case .responseTimedOut(let timeout):
      return "response timed out after \(timeout) seconds"
    case .noReply:
      return "no reply"
    }
  }
}

/// Sends one line-delimited JSON request and decodes one JSON response.
public struct LineSocketClientTransport<Request: Encodable, Response: Decodable> {
  /// The socket path for this line socket client transport.
  public let socketPath: String
  /// The response timeout for this line socket client transport.
  public let responseTimeout: TimeInterval
  /// The max response bytes for this line socket client transport.
  public let maxResponseBytes: Int

  /// The make encoder for this line socket client transport.
  private let makeEncoder: @Sendable () -> JSONEncoder
  /// The make decoder for this line socket client transport.
  private let makeDecoder: @Sendable () -> JSONDecoder

  /// Creates a new client transport for the given socket path.
  public init(
    socketPath: String,
    responseTimeout: TimeInterval = 5,
    maxResponseBytes: Int = LineDelimitedJSONDecoder<Response>.defaultMaxLineBytes,
    makeEncoder: @escaping @Sendable () -> JSONEncoder = {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      return encoder
    },
    makeDecoder: @escaping @Sendable () -> JSONDecoder = {
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      return decoder
    }
  ) {
    self.socketPath = socketPath
    self.responseTimeout = normalizedSocketTimeout(responseTimeout)
    self.maxResponseBytes = max(1, maxResponseBytes)
    self.makeEncoder = makeEncoder
    self.makeDecoder = makeDecoder
  }

  /// Sends one request and returns one decoded response.
  public func send(request: Request) throws -> Response {
    let encoder = makeEncoder()

    guard let payload = try? encoder.encode(request) else {
      throw LineSocketClientTransportError.encodeFailed
    }

    let deadline = monotonicPollDeadline(after: responseTimeout)
    let fd = try connectSocket(deadline: deadline)
    defer { close(fd) }

    try writeRequest(payload + Data([0x0A]), to: fd, deadline: deadline)
    return try readOneResponse(from: fd, deadline: deadline)
  }

  /// Returns the connect socket.
  private func connectSocket(deadline: UInt64) throws -> Int32 {
    do {
      return try openConnectedUnixSocket(
        at: socketPath,
        timeout: responseTimeout,
        deadline: deadline,
        restoreBlocking: false
      )
    } catch let error as UnixSocketConnectError {
      if case .timedOut(let timeout) = error {
        throw LineSocketClientTransportError.connectionTimedOut(timeout)
      }
      if case .createSocket = error {
        throw LineSocketClientTransportError.socketFailed
      }
      throw LineSocketClientTransportError.connectFailed(error)
    } catch {
      throw error
    }
  }

  /// Writes the complete request without exceeding the operation deadline.
  private func writeRequest(_ data: Data, to fd: Int32, deadline: UInt64) throws {
    guard !data.isEmpty else { return }

    try data.withUnsafeBytes { rawBuffer in
      guard let baseAddress = rawBuffer.baseAddress else {
        throw LineSocketClientTransportError.writeFailed("request buffer is unavailable")
      }

      var sent = 0
      while sent < data.count {
        let count = Darwin.write(fd, baseAddress.advanced(by: sent), data.count - sent)

        if count > 0 {
          sent += count
          continue
        }

        if count == 0 {
          throw LineSocketClientTransportError.writeFailed("socket write returned zero bytes")
        }

        let errnoValue = errno
        if errnoValue == EINTR {
          continue
        }

        if errnoValue == EAGAIN || errnoValue == EWOULDBLOCK {
          try waitForWritable(fd: fd, deadline: deadline)
          continue
        }

        throw LineSocketClientTransportError.writeFailed(errnoDescription(errnoValue))
      }
    }
  }

  /// Reads bytes until one response line decodes or EOF is reached.
  private func readOneResponse(from fd: Int32, deadline: UInt64) throws -> Response {
    var lineDecoder = LineDelimitedJSONDecoder<Response>(
      decoder: makeDecoder(),
      maxLineBytes: maxResponseBytes
    )
    var buffer = [UInt8](repeating: 0, count: 1024)

    while true {
      try waitForReadable(fd: fd, deadline: deadline)

      let count = read(fd, &buffer, buffer.count)
      if count < 0 {
        let errnoValue = errno
        if errnoValue == EINTR || errnoValue == EAGAIN || errnoValue == EWOULDBLOCK {
          continue
        }
        throw LineSocketClientTransportError.readFailed(errnoDescription(errnoValue))
      }

      if count == 0 {
        return try decodeOneResult(lineDecoder.flush())
      }

      let results = lineDecoder.append(buffer.prefix(count))
      if !results.isEmpty {
        return try decodeOneResult(results)
      }
    }
  }

  /// Waits until the socket can accept more request bytes.
  private func waitForWritable(fd: Int32, deadline: UInt64) throws {
    while true {
      let timeoutMilliseconds = remainingPollMilliseconds(until: deadline)
      guard timeoutMilliseconds > 0 else {
        throw LineSocketClientTransportError.writeTimedOut(responseTimeout)
      }

      var descriptor = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
      let result = poll(&descriptor, 1, timeoutMilliseconds)

      if result > 0 {
        let revents = Int32(descriptor.revents)
        if (revents & POLLOUT) != 0, (revents & (POLLERR | POLLHUP | POLLNVAL)) == 0 {
          return
        }
        throw LineSocketClientTransportError.writeFailed(
          "socket became unavailable while writing (poll events \(revents))"
        )
      }

      if result == 0 {
        throw LineSocketClientTransportError.writeTimedOut(responseTimeout)
      }

      if errno == EINTR {
        continue
      }

      throw LineSocketClientTransportError.writeFailed(errnoDescription(errno))
    }
  }

  /// Waits until the socket has data to read or the operation deadline expires.
  private func waitForReadable(fd: Int32, deadline: UInt64) throws {
    while true {
      let timeoutMilliseconds = remainingPollMilliseconds(until: deadline)
      guard timeoutMilliseconds > 0 else {
        throw LineSocketClientTransportError.responseTimedOut(responseTimeout)
      }

      var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
      let result = poll(&descriptor, 1, timeoutMilliseconds)

      if result > 0 {
        let revents = Int32(descriptor.revents)
        if (revents & (POLLIN | POLLHUP)) != 0 {
          return
        }
        throw LineSocketClientTransportError.readFailed(
          "socket became unavailable while reading (poll events \(revents))"
        )
      }

      if result == 0 {
        throw LineSocketClientTransportError.responseTimedOut(responseTimeout)
      }

      if errno == EINTR {
        continue
      }

      throw LineSocketClientTransportError.readFailed(errnoDescription(errno))
    }
  }

  /// Returns the first decoded response from a line decoder result list.
  private func decodeOneResult(_ results: [Result<Response, Error>]) throws -> Response {
    guard let result = results.first else {
      throw LineSocketClientTransportError.noReply
    }

    do {
      return try result.get()
    } catch {
      throw LineSocketClientTransportError.decodeFailed("\(error)")
    }
  }

  /// Returns the errno description.
  private func errnoDescription(_ value: Int32) -> String {
    "\(String(cString: strerror(value))) (errno \(value))"
  }
}
