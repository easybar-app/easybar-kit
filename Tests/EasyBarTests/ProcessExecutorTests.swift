import Darwin
import EasyBarShared
import Foundation
import XCTest

final class ProcessExecutorTests: XCTestCase {
  func testSpawnValidationRejectsEmbeddedNULArguments() {
    XCTAssertThrowsError(
      try ProcessSpawnSupport.validate(
        executablePath: "/usr/bin/printf",
        arguments: ["printf", "safe\0hidden"],
        environment: ["PATH": "/usr/bin:/bin"]
      )
    ) { error in
      XCTAssertEqual(
        error as? ProcessSpawnError,
        .embeddedNUL(field: "process argument 1")
      )
    }
  }

  func testSpawnValidationRejectsMalformedEnvironment() {
    XCTAssertThrowsError(
      try ProcessSpawnSupport.validateEnvironment(["BAD=KEY": "value"])
    ) { error in
      XCTAssertEqual(error as? ProcessSpawnError, .invalidEnvironmentKey("BAD=KEY"))
    }

    XCTAssertThrowsError(
      try ProcessSpawnSupport.validateEnvironment(["GOOD_KEY": "safe\0hidden"])
    ) { error in
      XCTAssertEqual(
        error as? ProcessSpawnError,
        .embeddedNUL(field: "process environment value for GOOD_KEY")
      )
    }
  }

  func testWaitStatusDecodingIsShared() {
    XCTAssertEqual(ProcessWaitSupport.decode(status: 7 << 8), .exited(code: 7))
    XCTAssertEqual(ProcessWaitSupport.decode(status: SIGTERM), .signaled(signal: SIGTERM))
  }

  func testSpawnDoesNotInheritUnrelatedParentDescriptors() throws {
    var leakPipe = [Int32](repeating: -1, count: 2)
    guard pipe(&leakPipe) == 0 else {
      throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
    defer {
      if leakPipe[0] >= 0 { close(leakPipe[0]) }
      if leakPipe[1] >= 0 { close(leakPipe[1]) }
    }

    let discardedErrorFD = open("/dev/null", O_WRONLY)
    guard discardedErrorFD >= 0 else {
      throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
    defer {
      if discardedErrorFD >= 0 { close(discardedErrorFD) }
    }

    var environment = ProcessInfo.processInfo.environment
    environment["LEAK_FD"] = String(leakPipe[1])
    let command = "if eval 'printf inherited >&$LEAK_FD'; then exit 42; else exit 0; fi"
    let processIdentifier = try ProcessSpawnSupport.spawn(
      executablePath: "/bin/sh",
      arguments: ["/bin/sh", "-c", command],
      environment: environment,
      standardErrorFileDescriptor: discardedErrorFD,
      createProcessGroup: false
    )

    close(leakPipe[1])
    leakPipe[1] = -1

    let observation = ProcessWaitSupport.wait(processIdentifier: processIdentifier)
    guard case .terminated(_, let reason) = observation else {
      return XCTFail("Expected child termination, got \(observation)")
    }
    XCTAssertEqual(reason, .exited(code: 0))

    var bytes = [UInt8](repeating: 0, count: 16)
    let count = bytes.withUnsafeMutableBytes { buffer in
      Darwin.read(leakPipe[0], buffer.baseAddress, buffer.count)
    }
    XCTAssertEqual(count, 0)
  }

  func testSuccessfulLeaderExitTerminatesBackgroundDescendant() throws {
    let logger = ProcessLogger(
      label: "process.executor.tests",
      minimumLevel: .error,
      outputStream: nil,
      errorStream: nil
    )
    let executor = ProcessExecutor(logger: logger)
    let command = "sleep 30 & child=$!; printf '%s' \"$child\""
    let startedAt = Date()

    let result = try executor.runSynchronously(
      ProcessExecutionRequest(
        executablePath: "/bin/sh",
        arguments: ["/bin/sh", "-c", command],
        environment: ProcessInfo.processInfo.environment,
        timeout: 2,
        standardOutputLimit: 1024,
        mergeStandardError: true
      )
    )

    let elapsed = Date().timeIntervalSince(startedAt)
    let childPID = try XCTUnwrap(
      Int32(String(decoding: result.standardOutput, as: UTF8.self))
    )

    XCTAssertEqual(result.outcome, .completed)
    XCTAssertEqual(result.termination, .exited(code: 0))
    XCTAssertLessThan(elapsed, 2)
    XCTAssertTrue(waitUntilProcessIsAbsent(childPID))
  }

  func testAlreadyCancelledExecutionDoesNotLaunchProcess() async {
    let logger = ProcessLogger(
      label: "process.executor.tests",
      minimumLevel: .error,
      outputStream: nil,
      errorStream: nil
    )
    let executor = ProcessExecutor(logger: logger)
    let markerURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("easybar-process-executor-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: markerURL) }

    let task = Task {
      do {
        try await Task.sleep(nanoseconds: 60_000_000_000)
      } catch {
        // Keep the task's cancelled state and enter the executor deterministically.
      }

      return try await executor.run(
        ProcessExecutionRequest(
          executablePath: "/usr/bin/touch",
          arguments: ["/usr/bin/touch", markerURL.path],
          environment: ProcessInfo.processInfo.environment,
          timeout: 2,
          standardOutputLimit: 1024
        )
      )
    }

    task.cancel()

    do {
      _ = try await task.value
      XCTFail("Expected the already-cancelled execution to throw")
    } catch is CancellationError {
      // Expected.
    } catch {
      XCTFail("Expected CancellationError, got \(error)")
    }

    XCTAssertFalse(FileManager.default.fileExists(atPath: markerURL.path))
  }

  private func waitUntilProcessIsAbsent(_ processIdentifier: Int32) -> Bool {
    for _ in 0..<100 {
      if kill(processIdentifier, 0) != 0, errno == ESRCH {
        return true
      }
      usleep(20_000)
    }
    return false
  }
}
