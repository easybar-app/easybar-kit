import Darwin
import EasyBarShared
import Foundation

/// Streaming client for `easybar metrics --watch`.
struct MetricsStreamClient {
  /// Unix-domain socket path used for the metrics stream.
  let socketPath: String

  /// Opens connected socket.
  private func openConnectedSocket() throws -> Int32 {
    do {
      return try openConnectedUnixSocket(at: socketPath)
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

  /// Opens a socket, sends the metrics request, and handles streamed messages line by line.
  func stream(
    request: IPC.Request,
    handleMessage: (IPC.Message) throws -> Void
  ) throws {
    let fd = try openConnectedSocket()

    defer { close(fd) }

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]

    guard let payload = try? encoder.encode(request) else {
      throw LineSocketClientTransportError.encodeFailed
    }

    guard writeAll(payload + Data([0x0A]), to: fd) else {
      throw LineSocketClientTransportError.writeFailed("socket write failed")
    }

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    var lineDecoder = LineDelimitedJSONDecoder<IPC.Message>(decoder: decoder)
    var buffer = [UInt8](repeating: 0, count: 4096)

    while true {
      let count = buffer.withUnsafeMutableBytes { rawBuffer -> Int in
        guard let baseAddress = rawBuffer.baseAddress else { return -1 }
        return read(fd, baseAddress, rawBuffer.count)
      }

      if count > 0 {
        for result in lineDecoder.append(buffer.prefix(count)) {
          try handleMessage(try result.get())
        }
        continue
      }

      if count == 0 {
        for result in lineDecoder.flush() {
          try handleMessage(try result.get())
        }
        return
      }

      if errno == EINTR {
        continue
      }

      throw LineSocketClientTransportError.readFailed(String(cString: strerror(errno)))
    }
  }
}
