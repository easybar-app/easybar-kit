import Darwin
import EasyBarShared
import Foundation

private enum LuaTransportLimits {
  static let maxLineBytes = 1024 * 1024
  static let maxAuthenticationBytes = 4096
  static let authenticationTimeout: TimeInterval = 2
  static let writeTimeout: TimeInterval = 1
  static let maxPendingWrites = 256
  static let maxPendingWriteBytes = 2 * 1024 * 1024
}

/// Handles dedicated socket transport plus stderr logging for the Lua runtime process.
///
/// The first accepted peer must prove knowledge of a per-launch token before it
/// can become the runtime connection. Outbound records use a bounded writer, and
/// shutdown closes the socket before queued work drains so a stalled Lua process
/// cannot block reload or grow memory without limit.
final class LuaTransport: @unchecked Sendable {
  /// Startup errors surfaced while preparing the transport.
  enum TransportError: LocalizedError {
    case startupFailed(String)

    var errorDescription: String? {
      switch self {
      case .startupFailed(let message):
        return message
      }
    }
  }

  private struct AuthenticationRecord: Decodable {
    let type: String
    let token: String
  }

  private struct State {
    var generation: UInt64 = 0
    var listener: OwnedUnixSocketListener?
    var clientWriter: BoundedSocketWriter?
    var errorPipe: Pipe?
    var acceptTask: Task<Void, Never>?
    var readTask: Task<Void, Never>?
    var stderrTask: Task<Void, Never>?
    var lineHandler: (@Sendable (String) -> Void)?
    var authenticationToken: String?
  }

  private let logger: ProcessLogger
  private let logBridge: LuaLogBridge
  private let metricsCoordinator: MetricsCoordinator
  private let state = LockedState(State())

  /// Creates one Lua transport.
  init(logger: ProcessLogger, metricsCoordinator: MetricsCoordinator = .shared) {
    self.logger = logger
    self.metricsCoordinator = metricsCoordinator
    self.logBridge = LuaLogBridge(logger: logger.child("runtime"))
  }

  /// Starts listening on the configured Lua socket and installs stderr handling.
  func startListening(
    socketPath: String,
    authenticationToken: String,
    error: Pipe,
    lineHandler: @escaping @Sendable (String) -> Void
  ) throws {
    shutdown()

    guard !authenticationToken.isEmpty else {
      throw TransportError.startupFailed("lua transport authentication token is empty")
    }

    let listener = try makeListeningSocket(at: socketPath)
    let generation = state.withLock { state -> UInt64 in
      state.listener = listener
      state.errorPipe = error
      state.lineHandler = lineHandler
      state.authenticationToken = authenticationToken
      state.generation &+= 1
      return state.generation
    }

    let stderrFD = error.fileHandleForReading.fileDescriptor
    let stderrTask = DetachedTask.run(priority: .utility) { [weak self] in
      guard let self else { return }
      self.readLinesFromFD(stderrFD, generation: generation) { [weak self] line in
        guard let self else { return }
        let classification = self.logBridge.handle(line)
        Task {
          await self.metricsCoordinator.recordLuaStderrLine(classification)
        }
      }
    }

    let acceptTask = DetachedTask.run(priority: .utility) { [weak self] in
      self?.acceptAuthenticatedConnection(generation: generation)
    }

    state.withLock { state in
      guard state.generation == generation else {
        stderrTask.cancel()
        acceptTask.cancel()
        return
      }
      state.stderrTask = stderrTask
      state.acceptTask = acceptTask
    }
  }

  /// Stops socket, stderr handling, and all active read tasks.
  func shutdown() {
    let snapshot = state.withLock { state -> State in
      state.generation &+= 1
      let snapshot = state
      state.listener = nil
      state.clientWriter = nil
      state.errorPipe = nil
      state.acceptTask = nil
      state.readTask = nil
      state.stderrTask = nil
      state.lineHandler = nil
      state.authenticationToken = nil
      return snapshot
    }

    snapshot.acceptTask?.cancel()
    snapshot.readTask?.cancel()
    snapshot.stderrTask?.cancel()

    snapshot.clientWriter?.close()
    if let listener = snapshot.listener {
      closeListeningUnixSocket(listener)
    }

    try? snapshot.errorPipe?.fileHandleForReading.close()
    try? snapshot.errorPipe?.fileHandleForWriting.close()
  }

  /// Sends one encoded event line to the Lua runtime socket.
  func send(_ string: String) {
    guard let data = (string + "\n").data(using: .utf8) else { return }

    let snapshot = state.withLock { state in
      (generation: state.generation, writer: state.clientWriter)
    }

    guard let writer = snapshot.writer else {
      logger.debug("cannot send event, lua socket not connected")
      return
    }

    let accepted = writer.enqueue(data) { [weak self, weak writer] error in
      guard let self, let writer else { return }
      if let error {
        self.logger.error(
          "failed writing to lua socket",
          .field("error", String(describing: error))
        )
        self.clearClientWriter(writer, generation: snapshot.generation)
        return
      }

      Task {
        await self.metricsCoordinator.recordLuaWrite()
      }
      self.logger.trace(
        "lua protocol message sent",
        .field("direction", "host_to_runtime"),
        .field("bytes", data.count - 1)
      )
    }

    guard accepted else {
      logger.warn(
        "dropping lua socket message because the write queue is full",
        .field("bytes", data.count),
        .field("max_messages", LuaTransportLimits.maxPendingWrites),
        .field("max_bytes", LuaTransportLimits.maxPendingWriteBytes)
      )
      clearClientWriter(writer, generation: snapshot.generation)
      return
    }
  }

  /// Creates and binds the listening Unix socket.
  private func makeListeningSocket(at socketPath: String) throws -> OwnedUnixSocketListener {
    do {
      let listener = try makeOwnedListeningUnixSocket(
        at: socketPath,
        backlog: 2,
        onChmodFailure: { [logger, socketPath] errnoValue in
          logger.warn(
            "lua socket chmod failed",
            .field("path", socketPath),
            .field("errno", errnoValue)
          )
        }
      )
      logger.debug("lua socket listening", .field("socket_path", socketPath))
      return listener
    } catch {
      throw TransportError.startupFailed(
        "lua socket setup failed path=\(socketPath) error=\(error)"
      )
    }
  }

  /// Accepts peers until one supplies the launch token for this generation.
  private func acceptAuthenticatedConnection(generation: UInt64) {
    while !Task.isCancelled {
      let snapshot = state.withLock { state in
        (
          listener: state.generation == generation ? state.listener : nil,
          token: state.generation == generation ? state.authenticationToken : nil
        )
      }
      guard let listener = snapshot.listener, let expectedToken = snapshot.token else { return }

      let clientFD = accept(listener.fd, nil, nil)
      guard clientFD >= 0 else {
        if shouldLogAcceptFailure(errnoValue: errno), isCurrent(generation: generation) {
          logger.error("lua socket accept failed", .field("errno", errno))
        }
        return
      }

      guard configureNoSigPipe(fd: clientFD), configureNonBlocking(fd: clientFD) else {
        logger.error("failed to configure lua client socket", .field("fd", clientFD))
        close(clientFD)
        continue
      }

      let writer = BoundedSocketWriter(
        fd: clientFD,
        label: "easybar.lua-transport.writer.\(generation)",
        writeTimeout: LuaTransportLimits.writeTimeout,
        maxPendingMessages: LuaTransportLimits.maxPendingWrites,
        maxPendingBytes: LuaTransportLimits.maxPendingWriteBytes
      )

      guard
        let initialPending = authenticate(
          fd: clientFD,
          expectedToken: expectedToken,
          generation: generation
        )
      else {
        logger.warn("rejected unauthenticated lua socket peer", .field("fd", clientFD))
        writer.close()
        continue
      }

      guard installClientWriter(writer, generation: generation) else {
        writer.close()
        return
      }

      startReadTask(
        writer: writer,
        generation: generation,
        initialPending: initialPending
      )
      logger.debug("lua socket connected", .field("fd", clientFD))
      return
    }
  }

  /// Validates the first line and returns bytes already read after that line.
  private func authenticate(
    fd: Int32,
    expectedToken: String,
    generation: UInt64
  ) -> Data? {
    let deadline = monotonicDeadline(after: LuaTransportLimits.authenticationTimeout)
    var pending = Data()
    var buffer = [UInt8](repeating: 0, count: 1024)

    while isCurrent(generation: generation) {
      guard waitForReadable(fd: fd, deadline: deadline) else { return nil }

      let count = buffer.withUnsafeMutableBytes { rawBuffer -> Int in
        guard let baseAddress = rawBuffer.baseAddress else { return -1 }
        return Darwin.read(fd, baseAddress, rawBuffer.count)
      }

      if count > 0 {
        pending.append(contentsOf: buffer.prefix(count))
        guard pending.count <= LuaTransportLimits.maxAuthenticationBytes else { return nil }
        guard let newline = pending.firstIndex(of: 0x0A) else { continue }

        let line = pending.prefix(upTo: newline)
        let remainderStart = pending.index(after: newline)
        let remainder = Data(pending[remainderStart...])
        guard
          let record = try? JSONDecoder().decode(AuthenticationRecord.self, from: Data(line)),
          record.type == "hello",
          constantTimeEqual(record.token, expectedToken)
        else {
          return nil
        }
        return remainder
      }

      if count == 0 { return nil }
      if errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK { continue }
      return nil
    }

    return nil
  }

  /// Installs the authenticated connection when it still belongs to this generation.
  private func installClientWriter(
    _ writer: BoundedSocketWriter,
    generation: UInt64
  ) -> Bool {
    state.withLock { state in
      guard
        state.generation == generation,
        state.clientWriter == nil,
        state.lineHandler != nil
      else { return false }
      state.clientWriter = writer
      return true
    }
  }

  /// Starts line decoding for one authenticated runtime connection.
  private func startReadTask(
    writer: BoundedSocketWriter,
    generation: UInt64,
    initialPending: Data
  ) {
    let lineHandler = state.withLock { state in
      state.generation == generation ? state.lineHandler : nil
    }
    guard let lineHandler else {
      clearClientWriter(writer, generation: generation)
      return
    }

    let readTask = DetachedTask.run(priority: .utility) { [weak self, weak writer] in
      guard let self, let writer else { return }
      self.readLinesFromFD(
        writer.fd,
        generation: generation,
        initialPending: initialPending
      ) { [weak self] line in
        Task {
          await self?.metricsCoordinator.recordLuaTransportLine()
        }
        self?.logger.trace(
          "lua protocol message received",
          .field("direction", "runtime_to_host"),
          .field("bytes", line.utf8.count)
        )
        lineHandler(line)
      }

      self.clearClientWriter(writer, generation: generation)
    }

    state.withLock { state in
      guard state.generation == generation, state.clientWriter === writer else {
        readTask.cancel()
        return
      }
      state.readTask = readTask
    }
  }

  /// Reads buffered newline-delimited UTF-8 lines from one fd until it closes.
  private func readLinesFromFD(
    _ fd: Int32,
    generation: UInt64,
    initialPending: Data = Data(),
    handleLine: @escaping @Sendable (String) -> Void
  ) {
    var pending = initialPending
    var isDroppingOversizedLine = false
    var buffer = [UInt8](repeating: 0, count: 4096)

    processPendingLines(
      &pending,
      isDroppingOversizedLine: &isDroppingOversizedLine,
      fd: fd,
      generation: generation,
      handleLine: handleLine
    )

    while !Task.isCancelled, isCurrent(generation: generation) {
      guard waitForReadable(fd: fd) else { return }

      let count = buffer.withUnsafeMutableBytes { rawBuffer -> Int in
        guard let baseAddress = rawBuffer.baseAddress else { return -1 }
        return Darwin.read(fd, baseAddress, rawBuffer.count)
      }

      if count > 0 {
        let bytes = buffer.prefix(count)

        if isDroppingOversizedLine {
          guard let newlineIndex = bytes.firstIndex(of: 0x0A) else { continue }

          pending.removeAll(keepingCapacity: true)
          let afterNewline = bytes.index(after: newlineIndex)
          if afterNewline < bytes.endIndex {
            pending.append(contentsOf: bytes[afterNewline...])
          }
          isDroppingOversizedLine = false
        } else {
          pending.append(contentsOf: bytes)
        }

        processPendingLines(
          &pending,
          isDroppingOversizedLine: &isDroppingOversizedLine,
          fd: fd,
          generation: generation,
          handleLine: handleLine
        )
        continue
      }

      if count == 0 {
        if !isDroppingOversizedLine, let line = decodeLine(from: pending[...]) {
          guard isCurrent(generation: generation) else { return }
          handleLine(line)
        }
        return
      }

      if errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK { continue }
      return
    }
  }

  /// Emits complete buffered lines and applies the per-record size limit.
  private func processPendingLines(
    _ pending: inout Data,
    isDroppingOversizedLine: inout Bool,
    fd: Int32,
    generation: UInt64,
    handleLine: @escaping @Sendable (String) -> Void
  ) {
    while let newlineIndex = pending.firstIndex(of: 0x0A) {
      let lineData = pending.prefix(upTo: newlineIndex)
      pending.removeSubrange(...newlineIndex)

      guard lineData.count <= LuaTransportLimits.maxLineBytes else {
        logger.warn(
          "dropping oversized lua transport line",
          .field("bytes", lineData.count),
          .field("max_bytes", LuaTransportLimits.maxLineBytes),
          .field("fd", fd)
        )
        continue
      }

      guard let line = decodeLine(from: lineData) else { continue }
      guard isCurrent(generation: generation) else { return }
      handleLine(line)
    }

    if pending.count > LuaTransportLimits.maxLineBytes {
      logger.warn(
        "dropping oversized lua transport line",
        .field("bytes", pending.count),
        .field("max_bytes", LuaTransportLimits.maxLineBytes),
        .field("fd", fd)
      )
      pending.removeAll(keepingCapacity: true)
      isDroppingOversizedLine = true
    }
  }

  /// Clears and closes one client only when it is still current.
  private func clearClientWriter(
    _ writer: BoundedSocketWriter,
    generation: UInt64
  ) {
    let shouldClose = state.withLock { state -> Bool in
      guard state.generation == generation, state.clientWriter === writer else { return false }
      state.clientWriter = nil
      state.readTask = nil
      return true
    }

    if shouldClose {
      writer.close()
    }
  }

  /// Returns whether the generation is still active.
  private func isCurrent(generation: UInt64) -> Bool {
    state.withLock { $0.generation == generation }
  }

  /// Decodes one non-empty UTF-8 line.
  private func decodeLine(from data: Data.SubSequence) -> String? {
    guard
      let line = String(data: data, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines),
      !line.isEmpty
    else {
      return nil
    }

    return line
  }

  /// Returns whether an `accept` failure is unexpected enough to log.
  private func shouldLogAcceptFailure(errnoValue: Int32) -> Bool {
    errnoValue != EINVAL && errnoValue != EBADF
  }

  /// Waits for readable input, polling periodically when no deadline is supplied.
  private func waitForReadable(fd: Int32, deadline: UInt64? = nil) -> Bool {
    var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)

    while !Task.isCancelled {
      let timeout = deadline.map { remainingMilliseconds(until: $0) } ?? 1_000
      if let deadline, timeout == 0, DispatchTime.now().uptimeNanoseconds >= deadline {
        return false
      }

      let result = poll(&descriptor, 1, timeout)
      if result > 0 {
        let events = Int32(descriptor.revents)
        if (events & POLLIN) != 0 { return true }
        if (events & (POLLERR | POLLHUP | POLLNVAL)) != 0 { return false }
        continue
      }
      if result == 0 {
        if deadline != nil { return false }
        continue
      }
      if errno == EINTR { continue }
      return false
    }
    return false
  }

  /// Creates a local monotonic deadline without exposing shared internal helpers.
  private func monotonicDeadline(after timeout: TimeInterval) -> UInt64 {
    let seconds = min(
      normalizedSocketTimeout(timeout),
      Double(UInt64.max / 1_000_000_000)
    )
    let nanoseconds = UInt64(seconds * 1_000_000_000)
    let (deadline, overflow) = DispatchTime.now().uptimeNanoseconds.addingReportingOverflow(
      nanoseconds
    )
    return overflow ? UInt64.max : deadline
  }

  /// Returns a poll-compatible number of milliseconds until a local deadline.
  private func remainingMilliseconds(until deadline: UInt64) -> Int32 {
    let now = DispatchTime.now().uptimeNanoseconds
    guard deadline > now else { return 0 }
    let remaining = deadline - now
    return Int32(min((remaining + 999_999) / 1_000_000, UInt64(Int32.max)))
  }

  /// Compares secrets without returning early on the first mismatching byte.
  private func constantTimeEqual(_ lhs: String, _ rhs: String) -> Bool {
    let left = Array(lhs.utf8)
    let right = Array(rhs.utf8)
    var difference = UInt64(left.count ^ right.count)
    let count = max(left.count, right.count)

    for index in 0..<count {
      let leftByte = index < left.count ? left[index] : 0
      let rightByte = index < right.count ? right[index] : 0
      difference |= UInt64(leftByte ^ rightByte)
    }
    return difference == 0
  }
}
