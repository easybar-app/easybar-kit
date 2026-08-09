import Darwin
import Foundation

/// Captured process output stream used in failure diagnostics.
public enum ProcessCapturedStream: String, Equatable, Sendable {
  case standardOutput
  case standardError
}

/// Terminal policy result for one short-lived process execution.
public enum ProcessExecutionOutcome: Equatable, Sendable {
  case completed
  case timedOut
  case cancelled
  case outputLimitExceeded(stream: ProcessCapturedStream)
  case readFailed(stream: ProcessCapturedStream, errno: Int32)
  case reapFailed(errno: Int32)
}

/// Validation and pipe failures raised before a process can be executed.
public enum ProcessExecutionError: Error, Equatable, LocalizedError, Sendable {
  case invalidTimeout
  case invalidOutputLimit
  case systemCall(operation: String, code: Int32)

  public var errorDescription: String? {
    switch self {
    case .invalidTimeout:
      return "process timeout must be finite and greater than zero"
    case .invalidOutputLimit:
      return "process output limits must be greater than zero"
    case .systemCall(let operation, let code):
      let message = String(cString: strerror(code))
      return "\(operation) failed: \(message) (errno=\(code))"
    }
  }
}

/// Immutable execution request consumed by `ProcessExecutor`.
public struct ProcessExecutionRequest: Sendable {
  public let executablePath: String
  public let arguments: [String]
  public let environment: [String: String]
  public let timeout: TimeInterval?
  public let standardOutputLimit: Int
  public let standardErrorLimit: Int
  public let mergeStandardError: Bool
  public let terminationGraceSeconds: TimeInterval
  public let pipeDrainGraceSeconds: TimeInterval
  public let finalReapGraceSeconds: TimeInterval

  public init(
    executablePath: String,
    arguments: [String],
    environment: [String: String],
    timeout: TimeInterval?,
    standardOutputLimit: Int,
    standardErrorLimit: Int? = nil,
    mergeStandardError: Bool = false,
    terminationGraceSeconds: TimeInterval = 0.15,
    pipeDrainGraceSeconds: TimeInterval = 0.05,
    finalReapGraceSeconds: TimeInterval = 1
  ) {
    self.executablePath = executablePath
    self.arguments = arguments
    self.environment = environment
    self.timeout = timeout
    self.standardOutputLimit = standardOutputLimit
    self.standardErrorLimit = standardErrorLimit ?? standardOutputLimit
    self.mergeStandardError = mergeStandardError
    self.terminationGraceSeconds = terminationGraceSeconds
    self.pipeDrainGraceSeconds = pipeDrainGraceSeconds
    self.finalReapGraceSeconds = finalReapGraceSeconds
  }
}

/// Captured output and termination state from one process execution.
public struct ProcessExecutionResult: Equatable, Sendable {
  public let standardOutput: Data
  public let standardError: Data
  public let termination: ProcessTerminationStatus
  public let outcome: ProcessExecutionOutcome
}

/// Runs one child in a dedicated process group with bounded output, cancellation, and cleanup.
public final class ProcessExecutor: @unchecked Sendable {
  private static let pollIntervalMilliseconds: Int32 = 20

  private final class CancellationState: @unchecked Sendable {
    private let state = LockedState(false)

    func cancel() {
      state.withLock { $0 = true }
    }

    var isCancelled: Bool {
      state.withLock { $0 }
    }
  }

  private struct OutputChannel {
    let stream: ProcessCapturedStream
    let limit: Int
    var fileDescriptor: Int32
    var data = Data()
    var exceededLimit = false
    var readError: Int32?

    var isOpen: Bool {
      fileDescriptor >= 0
    }

    mutating func close() {
      guard fileDescriptor >= 0 else { return }
      Darwin.close(fileDescriptor)
      fileDescriptor = -1
    }
  }

  private let logger: ProcessLogger

  /// Creates one shared process executor.
  public init(logger: ProcessLogger) {
    self.logger = logger
  }

  /// Executes one process without blocking the caller's cooperative executor thread.
  public func run(_ request: ProcessExecutionRequest) async throws -> ProcessExecutionResult {
    try Task.checkCancellation()
    let cancellation = CancellationState()
    if Task.isCancelled {
      cancellation.cancel()
    }

    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global(qos: .utility).async { [self] in
          do {
            continuation.resume(
              returning: try runSynchronously(request, cancellation: cancellation)
            )
          } catch {
            continuation.resume(throwing: error)
          }
        }
      }
    } onCancel: {
      cancellation.cancel()
    }
  }

  /// Executes one process on the current thread.
  public func runSynchronously(
    _ request: ProcessExecutionRequest
  ) throws -> ProcessExecutionResult {
    try runSynchronously(request, cancellation: CancellationState())
  }

  /// Executes one process and polls cancellation, output, and child state through one loop.
  private func runSynchronously(
    _ request: ProcessExecutionRequest,
    cancellation: CancellationState
  ) throws -> ProcessExecutionResult {
    try validate(request)

    if cancellation.isCancelled {
      throw CancellationError()
    }

    var standardOutputPipe = [Int32](repeating: -1, count: 2)
    guard pipe(&standardOutputPipe) == 0 else {
      throw ProcessExecutionError.systemCall(operation: "pipe(stdout)", code: errno)
    }

    var standardErrorPipe = [Int32](repeating: -1, count: 2)
    if !request.mergeStandardError, pipe(&standardErrorPipe) != 0 {
      let code = errno
      Darwin.close(standardOutputPipe[0])
      Darwin.close(standardOutputPipe[1])
      throw ProcessExecutionError.systemCall(operation: "pipe(stderr)", code: code)
    }

    do {
      try configureNonblocking(standardOutputPipe[0], operation: "fcntl(stdout)")
      if !request.mergeStandardError {
        try configureNonblocking(standardErrorPipe[0], operation: "fcntl(stderr)")
      }
    } catch {
      Darwin.close(standardOutputPipe[0])
      Darwin.close(standardOutputPipe[1])
      if !request.mergeStandardError {
        Darwin.close(standardErrorPipe[0])
        Darwin.close(standardErrorPipe[1])
      }
      throw error
    }

    var standardOutput = OutputChannel(
      stream: .standardOutput,
      limit: request.standardOutputLimit,
      fileDescriptor: standardOutputPipe[0]
    )
    var standardError = OutputChannel(
      stream: .standardError,
      limit: request.standardErrorLimit,
      fileDescriptor: request.mergeStandardError ? -1 : standardErrorPipe[0]
    )
    var standardOutputWriteFileDescriptor = standardOutputPipe[1]
    var standardErrorWriteFileDescriptor =
      request.mergeStandardError ? standardOutputPipe[1] : standardErrorPipe[1]

    defer {
      standardOutput.close()
      standardError.close()
      if standardErrorWriteFileDescriptor == standardOutputWriteFileDescriptor {
        standardErrorWriteFileDescriptor = -1
      }
      closeIfOpen(&standardOutputWriteFileDescriptor)
      closeIfOpen(&standardErrorWriteFileDescriptor)
    }

    let processIdentifier: pid_t
    do {
      processIdentifier = try ProcessSpawnSupport.spawn(
        executablePath: request.executablePath,
        arguments: request.arguments,
        environment: request.environment,
        standardOutputFileDescriptor: standardOutputWriteFileDescriptor,
        standardErrorFileDescriptor: standardErrorWriteFileDescriptor,
        closeFileDescriptors: [standardOutput.fileDescriptor, standardError.fileDescriptor],
        createProcessGroup: true
      )
    } catch {
      throw error
    }

    closeIfOpen(&standardOutputWriteFileDescriptor)
    if !request.mergeStandardError {
      closeIfOpen(&standardErrorWriteFileDescriptor)
    } else {
      standardErrorWriteFileDescriptor = -1
    }

    let processGroupIdentifier = processIdentifier
    let startedAt = monotonicNanoseconds()
    let timeoutDeadline = request.timeout.map {
      addingNanoseconds(to: startedAt, seconds: $0)
    }
    let terminationGrace = safeNanoseconds(request.terminationGraceSeconds)
    let pipeDrainGrace = safeNanoseconds(request.pipeDrainGraceSeconds)
    let finalReapGrace = safeNanoseconds(request.finalReapGraceSeconds)

    var termination: ProcessTerminationStatus?
    var outcome: ProcessExecutionOutcome?
    var sentTerminationSignal = false
    var sentKillSignal = false
    var forceKillDeadline: UInt64?
    var closePipesDeadline: UInt64?
    var finalCleanupDeadline: UInt64?

    func recordSignalFailure(_ delivery: ProcessSignalDelivery, signal: Int32) {
      guard !delivery.delivered, !delivery.targetWasMissing else { return }
      logger.warn(
        "failed to signal process tree",
        .field("pid", processIdentifier),
        .field("pgid", processGroupIdentifier),
        .field("signal", signal),
        .field("group_errno", delivery.processGroupError),
        .field("process_errno", delivery.processError)
      )
    }

    func beginCleanup(now: UInt64, leaderHasExited: Bool) {
      guard !sentTerminationSignal else { return }
      sentTerminationSignal = true

      let delivery = ProcessSignalSupport.send(
        SIGTERM,
        processIdentifier: processIdentifier,
        processGroupIdentifier: processGroupIdentifier,
        fallbackToProcess: !leaderHasExited
      )
      recordSignalFailure(delivery, signal: SIGTERM)

      forceKillDeadline = addingNanoseconds(to: now, nanoseconds: terminationGrace)
      closePipesDeadline = addingNanoseconds(
        to: forceKillDeadline ?? now,
        nanoseconds: pipeDrainGrace
      )
      finalCleanupDeadline = addingNanoseconds(
        to: closePipesDeadline ?? now,
        nanoseconds: finalReapGrace
      )
    }

    while true {
      let loopStartedAt = monotonicNanoseconds()

      if termination == nil {
        switch ProcessWaitSupport.wait(
          processIdentifier: processIdentifier,
          options: WNOHANG
        ) {
        case .running:
          break
        case .terminated(_, let reason):
          termination = reason
          beginCleanup(now: loopStartedAt, leaderHasExited: true)
        case .failed(let errnoValue):
          termination = .reapFailed(errno: errnoValue)
          if outcome == nil {
            outcome = .reapFailed(errno: errnoValue)
          }
          beginCleanup(now: loopStartedAt, leaderHasExited: true)
        }
      }

      if outcome == nil, cancellation.isCancelled {
        outcome = .cancelled
        beginCleanup(now: loopStartedAt, leaderHasExited: termination != nil)
      }

      if outcome == nil, let timeoutDeadline, loopStartedAt >= timeoutDeadline {
        outcome = .timedOut
        beginCleanup(now: loopStartedAt, leaderHasExited: termination != nil)
      }

      pollAndDrain(
        standardOutput: &standardOutput,
        standardError: &standardError,
        timeoutMilliseconds: Self.pollIntervalMilliseconds
      )

      if outcome == nil, let readError = standardOutput.readError {
        outcome = .readFailed(stream: .standardOutput, errno: readError)
        beginCleanup(now: monotonicNanoseconds(), leaderHasExited: termination != nil)
      }
      if outcome == nil, let readError = standardError.readError {
        outcome = .readFailed(stream: .standardError, errno: readError)
        beginCleanup(now: monotonicNanoseconds(), leaderHasExited: termination != nil)
      }
      if outcome == nil, standardOutput.exceededLimit {
        outcome = .outputLimitExceeded(stream: .standardOutput)
        beginCleanup(now: monotonicNanoseconds(), leaderHasExited: termination != nil)
      }
      if outcome == nil, standardError.exceededLimit {
        outcome = .outputLimitExceeded(stream: .standardError)
        beginCleanup(now: monotonicNanoseconds(), leaderHasExited: termination != nil)
      }

      let now = monotonicNanoseconds()
      let processGroupIsRunning = ProcessSignalSupport.isRunning(
        processGroupIdentifier: processGroupIdentifier
      )

      if sentTerminationSignal,
        !sentKillSignal,
        processGroupIsRunning,
        let forceKillDeadline,
        now >= forceKillDeadline
      {
        sentKillSignal = true
        let delivery = ProcessSignalSupport.send(
          SIGKILL,
          processIdentifier: processIdentifier,
          processGroupIdentifier: processGroupIdentifier,
          fallbackToProcess: termination == nil
        )
        recordSignalFailure(delivery, signal: SIGKILL)
      }

      if sentTerminationSignal, let closePipesDeadline, now >= closePipesDeadline {
        drain(&standardOutput)
        drain(&standardError)
        standardOutput.close()
        standardError.close()
      }

      if let termination,
        !standardOutput.isOpen,
        !standardError.isOpen,
        !ProcessSignalSupport.isRunning(processGroupIdentifier: processGroupIdentifier)
      {
        return ProcessExecutionResult(
          standardOutput: standardOutput.data,
          standardError: standardError.data,
          termination: termination,
          outcome: outcome ?? .completed
        )
      }

      if let finalCleanupDeadline, now >= finalCleanupDeadline {
        if termination == nil {
          termination = .reapFailed(errno: ETIMEDOUT)
          if outcome == nil {
            outcome = .reapFailed(errno: ETIMEDOUT)
          }
        }

        drain(&standardOutput)
        drain(&standardError)
        standardOutput.close()
        standardError.close()

        return ProcessExecutionResult(
          standardOutput: standardOutput.data,
          standardError: standardError.data,
          termination: termination ?? .reapFailed(errno: ETIMEDOUT),
          outcome: outcome ?? .reapFailed(errno: ETIMEDOUT)
        )
      }
    }
  }

  /// Validates executor-specific limits in addition to the spawn payload.
  private func validate(_ request: ProcessExecutionRequest) throws {
    if hasInvalidTimeout(request) {
      throw ProcessExecutionError.invalidTimeout
    }
    guard request.standardOutputLimit > 0, request.standardErrorLimit > 0 else {
      throw ProcessExecutionError.invalidOutputLimit
    }

    try ProcessSpawnSupport.validate(
      executablePath: request.executablePath,
      arguments: request.arguments,
      environment: request.environment
    )
  }

  private func hasInvalidTimeout(_ request: ProcessExecutionRequest) -> Bool {
    guard let timeout = request.timeout else { return false }
    return !timeout.isFinite || timeout <= 0
  }

  /// Configures one pipe reader as nonblocking.
  private func configureNonblocking(_ fileDescriptor: Int32, operation: String) throws {
    let flags = fcntl(fileDescriptor, F_GETFL)
    guard flags >= 0 else {
      throw ProcessExecutionError.systemCall(operation: operation, code: errno)
    }
    guard fcntl(fileDescriptor, F_SETFL, flags | O_NONBLOCK) >= 0 else {
      throw ProcessExecutionError.systemCall(operation: operation, code: errno)
    }
  }

  /// Polls every open output channel and drains all bytes currently available.
  private func pollAndDrain(
    standardOutput: inout OutputChannel,
    standardError: inout OutputChannel,
    timeoutMilliseconds: Int32
  ) {
    var descriptors: [pollfd] = []
    var streams: [ProcessCapturedStream] = []

    if standardOutput.isOpen {
      descriptors.append(
        pollfd(
          fd: standardOutput.fileDescriptor,
          events: Int16(POLLIN | POLLHUP | POLLERR),
          revents: 0
        )
      )
      streams.append(.standardOutput)
    }
    if standardError.isOpen {
      descriptors.append(
        pollfd(
          fd: standardError.fileDescriptor,
          events: Int16(POLLIN | POLLHUP | POLLERR),
          revents: 0
        )
      )
      streams.append(.standardError)
    }

    guard !descriptors.isEmpty else {
      usleep(useconds_t(max(0, timeoutMilliseconds) * 1_000))
      return
    }

    let result = descriptors.withUnsafeMutableBufferPointer { buffer in
      poll(buffer.baseAddress, nfds_t(buffer.count), timeoutMilliseconds)
    }

    if result < 0 {
      let errnoValue = errno
      guard errnoValue != EINTR else { return }
      if standardOutput.isOpen {
        standardOutput.readError = errnoValue
      } else if standardError.isOpen {
        standardError.readError = errnoValue
      }
      return
    }

    guard result > 0 else { return }

    for (index, descriptor) in descriptors.enumerated() where descriptor.revents != 0 {
      switch streams[index] {
      case .standardOutput:
        drain(&standardOutput)
      case .standardError:
        drain(&standardError)
      }
    }
  }

  /// Reads one nonblocking channel through EOF, EAGAIN, or a hard failure.
  private func drain(_ channel: inout OutputChannel) {
    guard channel.isOpen else { return }

    var buffer = [UInt8](repeating: 0, count: 4096)
    while true {
      let bytesRead = buffer.withUnsafeMutableBytes { rawBuffer in
        guard let baseAddress = rawBuffer.baseAddress else { return 0 }
        return Darwin.read(channel.fileDescriptor, baseAddress, rawBuffer.count)
      }

      if bytesRead > 0 {
        let remainingBytes = max(0, channel.limit - channel.data.count)
        if remainingBytes > 0 {
          channel.data.append(contentsOf: buffer.prefix(min(bytesRead, remainingBytes)))
        }
        if bytesRead > remainingBytes {
          channel.exceededLimit = true
        }
        continue
      }

      if bytesRead == 0 {
        channel.close()
        return
      }

      let errnoValue = errno
      if errnoValue == EINTR {
        continue
      }
      if errnoValue == EAGAIN || errnoValue == EWOULDBLOCK {
        return
      }

      channel.readError = errnoValue
      channel.close()
      return
    }
  }

  /// Returns monotonic nanoseconds without wall-clock changes.
  private func monotonicNanoseconds() -> UInt64 {
    DispatchTime.now().uptimeNanoseconds
  }

  /// Converts one nonnegative duration to a bounded nanosecond value.
  private func safeNanoseconds(_ seconds: TimeInterval) -> UInt64 {
    guard seconds.isFinite, seconds > 0 else { return 0 }
    let value = seconds * 1_000_000_000
    guard value.isFinite, value < Double(UInt64.max) else { return UInt64.max }
    return UInt64(value)
  }

  /// Adds one bounded duration to one monotonic timestamp.
  private func addingNanoseconds(to base: UInt64, seconds: TimeInterval) -> UInt64 {
    addingNanoseconds(to: base, nanoseconds: safeNanoseconds(seconds))
  }

  /// Adds nanoseconds without integer overflow.
  private func addingNanoseconds(to base: UInt64, nanoseconds: UInt64) -> UInt64 {
    let (result, overflow) = base.addingReportingOverflow(nanoseconds)
    return overflow ? UInt64.max : result
  }

  /// Closes one raw descriptor and marks it unavailable.
  private func closeIfOpen(_ fileDescriptor: inout Int32) {
    guard fileDescriptor >= 0 else { return }
    Darwin.close(fileDescriptor)
    fileDescriptor = -1
  }
}
