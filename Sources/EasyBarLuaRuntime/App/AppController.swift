import Darwin
import EasyBarShared
import Foundation

/// App-level controller for the Lua runtime process.
///
/// This bootstrap authenticates to the host with a per-launch token before it
/// maps the transport onto standard input and output and replaces itself with
/// the configured Lua interpreter.
@main
final class AppController {
  private static let transportTokenEnvironmentKey = "EASYBAR_LUA_TRANSPORT_TOKEN"

  /// Captures the command-line inputs for the Lua runtime process.
  private struct RuntimeArguments {
    let socketPath: String
    let luaPath: String
    let runtimePath: String
    let widgetsPath: String
    let defaultCommandTimeoutSeconds: String
    let defaultCommandMaxOutputBytes: String
  }

  private struct AuthenticationRecord: Encodable {
    let type = "hello"
    let token: String
  }

  /// Runs the Lua runtime process.
  static func main() {
    Darwin.exit(AppController().run())
  }

  /// Starts the runtime bootstrap and returns the process exit code.
  func run() -> Int32 {
    do {
      let arguments = try parseArguments()
      let token = try transportAuthenticationToken()
      let socketFileDescriptor = try connectSocket(path: arguments.socketPath)
      try authenticateSocket(fd: socketFileDescriptor, token: token)
      guard configureBlocking(fd: socketFileDescriptor) else {
        close(socketFileDescriptor)
        throw RuntimeBootstrapError.blockingModeFailed(errno: errno)
      }
      _ = Self.transportTokenEnvironmentKey.withCString { key in
        unsetenv(key)
      }
      try duplicateTransportToStandardIO(fd: socketFileDescriptor)
      try execLua(arguments)
    } catch {
      fputs("EasyBarLuaRuntime: \(error.localizedDescription)\n", stderr)
      return 1
    }
  }

  /// Parses the runtime process command-line arguments.
  private func parseArguments() throws -> RuntimeArguments {
    let args = Array(CommandLine.arguments.dropFirst())
    guard args.count == 6 else {
      throw RuntimeBootstrapError.usage
    }

    return RuntimeArguments(
      socketPath: args[0],
      luaPath: args[1],
      runtimePath: args[2],
      widgetsPath: args[3],
      defaultCommandTimeoutSeconds: args[4],
      defaultCommandMaxOutputBytes: args[5]
    )
  }

  /// Reads the required launch token without forwarding it into the Lua process.
  private func transportAuthenticationToken() throws -> String {
    guard
      let token = ProcessInfo.processInfo.environment[Self.transportTokenEnvironmentKey],
      !token.isEmpty
    else {
      throw RuntimeBootstrapError.missingAuthenticationToken
    }
    return token
  }

  /// Connects the runtime process to the configured Lua transport socket.
  private func connectSocket(path: String) throws -> Int32 {
    do {
      return try openConnectedUnixSocket(at: path, timeout: 5, keepNonBlocking: true)
    } catch {
      throw RuntimeBootstrapError.connectFailed(path: path, message: "\(error)")
    }
  }

  /// Sends the token record before any Lua protocol data can reach the host.
  private func authenticateSocket(fd: Int32, token: String) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(AuthenticationRecord(token: token)) + Data([0x0A])

    if let error = writeAll(data, to: fd, timeout: 2) {
      close(fd)
      throw RuntimeBootstrapError.authenticationFailed(message: String(describing: error))
    }
  }

  /// Maps the connected transport socket onto standard input and output.
  private func duplicateTransportToStandardIO(fd: Int32) throws {
    guard dup2(fd, STDIN_FILENO) >= 0 else {
      let message = String(cString: strerror(errno))
      close(fd)
      throw RuntimeBootstrapError.dup2Failed(stream: "stdin", message: message)
    }

    guard dup2(fd, STDOUT_FILENO) >= 0 else {
      let message = String(cString: strerror(errno))
      close(fd)
      throw RuntimeBootstrapError.dup2Failed(stream: "stdout", message: message)
    }

    if fd > STDERR_FILENO {
      close(fd)
    }
  }

  /// Replaces the runtime process with the configured Lua interpreter.
  private func execLua(_ arguments: RuntimeArguments) throws -> Never {
    var argv: [UnsafeMutablePointer<CChar>?] = [
      strdup(arguments.luaPath),
      strdup(arguments.runtimePath),
      strdup(arguments.widgetsPath),
      strdup(arguments.defaultCommandTimeoutSeconds),
      strdup(arguments.defaultCommandMaxOutputBytes),
    ]

    argv.append(nil)

    defer {
      for case let pointer? in argv {
        free(pointer)
      }
    }

    let execResult = argv.withUnsafeMutableBufferPointer { buffer in
      execvp(arguments.luaPath, buffer.baseAddress)
    }

    guard execResult == -1 else {
      throw RuntimeBootstrapError.execUnexpectedlyReturned
    }

    let message = String(cString: strerror(errno))
    throw RuntimeBootstrapError.execFailed(luaPath: arguments.luaPath, message: message)
  }
}

/// Startup errors produced by the Lua runtime bootstrap process.
private enum RuntimeBootstrapError: LocalizedError {
  case usage
  case missingAuthenticationToken
  case connectFailed(path: String, message: String)
  case authenticationFailed(message: String)
  case blockingModeFailed(errno: Int32)
  case dup2Failed(stream: String, message: String)
  case execUnexpectedlyReturned
  case execFailed(luaPath: String, message: String)

  /// Returns the user-facing startup error message.
  var errorDescription: String? {
    switch self {
    case .usage:
      return
        "usage: EasyBarLuaRuntime <socket-path> <lua-path> <runtime-path> <widgets-path> <default-command-timeout-seconds> <default-command-max-output-bytes>"
    case .missingAuthenticationToken:
      return "missing Lua transport authentication token"
    case .connectFailed(let path, let message):
      return "connect failed path=\(path) error=\(message)"
    case .authenticationFailed(let message):
      return "transport authentication failed error=\(message)"
    case .blockingModeFailed(let errnoValue):
      return "failed to restore blocking socket mode errno=\(errnoValue)"
    case .dup2Failed(let stream, let message):
      return "dup2 \(stream) failed error=\(message)"
    case .execUnexpectedlyReturned:
      return "exec unexpectedly returned"
    case .execFailed(let luaPath, let message):
      return "exec failed lua=\(luaPath) error=\(message)"
    }
  }
}
