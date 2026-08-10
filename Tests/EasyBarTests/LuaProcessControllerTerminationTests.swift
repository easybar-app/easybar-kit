import EasyBarShared
import Foundation
import XCTest

@testable import EasyBarKit

private actor AsyncTestBarrier {
  private let participantCount: Int
  private var continuations: [CheckedContinuation<Void, Never>] = []

  init(participantCount: Int) {
    self.participantCount = participantCount
  }

  func wait() async {
    await withCheckedContinuation { continuation in
      if continuations.count + 1 == participantCount {
        let waiting = continuations
        continuations.removeAll(keepingCapacity: false)
        continuation.resume()
        for continuation in waiting {
          continuation.resume()
        }
      } else {
        continuations.append(continuation)
      }
    }
  }
}

final class LuaProcessControllerTerminationTests: XCTestCase, @unchecked Sendable {
  func testUnexpectedExitReportsExitCode() async throws {
    let scriptURL = try makeExecutableScript("exit 7")
    defer { try? FileManager.default.removeItem(at: scriptURL.deletingLastPathComponent()) }

    let controller = LuaProcessController(
      logger: ProcessLogger(label: "lua.termination.tests", minimumLevel: .error)
    )
    let resources = LuaProcessController.LaunchResources()
    defer { close(resources) }

    let terminated = expectation(description: "unexpected termination delivered")
    let result = LockedState<LuaProcessController.Termination?>(nil)

    XCTAssertNotNil(
      controller.start(
        context: makeContext(executablePath: scriptURL.path),
        resources: resources,
        terminationHandler: { termination in
          result.withLock { $0 = termination }
          terminated.fulfill()
        }
      )
    )

    await fulfillment(of: [terminated], timeout: 2)

    let termination = try XCTUnwrap(result.withLock { $0 })
    XCTAssertEqual(termination.reason, .exited(code: 7))
    XCTAssertFalse(termination.wasRequested)
    XCTAssertNil(controller.processIdentifier)
  }

  func testConcurrentStartsReserveOnlyOneRuntime() async throws {
    let scriptURL = try makeExecutableScript("while true; do sleep 1; done")
    defer { try? FileManager.default.removeItem(at: scriptURL.deletingLastPathComponent()) }

    let controller = LuaProcessController(
      logger: ProcessLogger(label: "lua.termination.tests", minimumLevel: .error)
    )
    let context = makeContext(executablePath: scriptURL.path)
    let resources = [
      LuaProcessController.LaunchResources(),
      LuaProcessController.LaunchResources(),
    ]
    defer {
      for resource in resources {
        close(resource)
      }
    }

    let startBarrier = AsyncTestBarrier(participantCount: resources.count)
    let starts = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
      for resource in resources {
        group.addTask {
          await startBarrier.wait()
          return controller.start(
            context: context,
            resources: resource,
            terminationHandler: { _ in }
          ) != nil
        }
      }

      var results: [Bool] = []
      for await result in group {
        results.append(result)
      }
      return results
    }

    XCTAssertEqual(starts.filter { $0 }.count, 1)
    XCTAssertNotNil(controller.processIdentifier)
    await controller.shutdownAndWait()
    XCTAssertNil(controller.processIdentifier)
  }

  func testRecoveryTerminationRemainsUnexpected() async throws {
    let scriptURL = try makeExecutableScript("while true; do sleep 1; done")
    defer { try? FileManager.default.removeItem(at: scriptURL.deletingLastPathComponent()) }

    let controller = LuaProcessController(
      logger: ProcessLogger(label: "lua.termination.tests", minimumLevel: .error)
    )
    let resources = LuaProcessController.LaunchResources()
    defer { close(resources) }

    let terminated = expectation(description: "recovery termination delivered")
    let result = LockedState<LuaProcessController.Termination?>(nil)

    XCTAssertNotNil(
      controller.start(
        context: makeContext(executablePath: scriptURL.path),
        resources: resources,
        terminationHandler: { termination in
          result.withLock { $0 = termination }
          terminated.fulfill()
        }
      )
    )

    XCTAssertTrue(controller.terminateForRecovery())
    await fulfillment(of: [terminated], timeout: 2)

    let termination = try XCTUnwrap(result.withLock { $0 })
    XCTAssertFalse(termination.wasRequested)
    XCTAssertNil(controller.processIdentifier)
  }

  func testShutdownMarksTerminationAsRequested() async throws {
    let scriptURL = try makeExecutableScript("while true; do sleep 1; done")
    defer { try? FileManager.default.removeItem(at: scriptURL.deletingLastPathComponent()) }

    let controller = LuaProcessController(
      logger: ProcessLogger(label: "lua.termination.tests", minimumLevel: .error)
    )
    let resources = LuaProcessController.LaunchResources()
    defer { close(resources) }

    let terminated = expectation(description: "requested termination delivered")
    let result = LockedState<LuaProcessController.Termination?>(nil)

    XCTAssertNotNil(
      controller.start(
        context: makeContext(executablePath: scriptURL.path),
        resources: resources,
        terminationHandler: { termination in
          result.withLock { $0 = termination }
          terminated.fulfill()
        }
      )
    )

    await controller.shutdownAndWait()
    await fulfillment(of: [terminated], timeout: 2)

    let termination = try XCTUnwrap(result.withLock { $0 })
    XCTAssertTrue(termination.wasRequested)
    XCTAssertNil(controller.processIdentifier)
  }

  private func makeContext(executablePath: String) -> LuaProcessController.LaunchContext {
    LuaProcessController.LaunchContext(
      runtimeAgentPath: executablePath,
      runtimePath: "/tmp/runtime.lua",
      luaPath: "/usr/bin/lua",
      luaSocketPath: "/tmp/easybar-test.sock",
      transportAuthenticationToken: "test-token",
      widgetsPath: "/tmp/widgets",
      defaultCommandTimeoutSeconds: 5,
      defaultCommandMaxOutputBytes: 65_536,
      environment: [:]
    )
  }

  private func makeExecutableScript(_ body: String) throws -> URL {
    let directoryURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("easybar-lua-termination-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: directoryURL,
      withIntermediateDirectories: true
    )

    let scriptURL = directoryURL.appendingPathComponent("runtime-agent.sh")
    try "#!/bin/sh\n\(body)\n".write(to: scriptURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755],
      ofItemAtPath: scriptURL.path
    )
    return scriptURL
  }

  private func close(_ resources: LuaProcessController.LaunchResources) {
    try? resources.error.fileHandleForReading.close()
    try? resources.error.fileHandleForWriting.close()
  }
}
