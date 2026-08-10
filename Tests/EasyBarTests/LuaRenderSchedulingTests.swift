import EasyBarShared
import Foundation
import XCTest

@testable import EasyBarKit

final class LuaRenderSchedulingTests: LuaRenderRuntimeTestCase, @unchecked Sendable {
  func testSpawnAsyncEmitsDirectArgumentVector() async throws {
    let widgetsDirectoryURL = try makeWidgetsDirectory()
    try """
    easybar.add("item", "result", { position = "right", label = "idle" })
    easybar.subscribe("result", { easybar.events.forced }, function()
      easybar.spawn_async({ "printf", "%s", "$HOME; echo unsafe" }, {}, function(output, code)
        easybar.set("result", { label = output .. ":" .. tostring(code) })
      end)
    end)
    """.write(
      to: widgetsDirectoryURL.appendingPathComponent("spawn.lua"),
      atomically: true,
      encoding: .utf8
    )

    let runtimeController = LuaProcessController(
      logger: ProcessLogger(label: "lua.spawn-async.test", minimumLevel: .error)
    )
    let runtimePath = try XCTUnwrap(runtimeController.resolvedRuntimePath())
    let recorder = RuntimeUpdateRecorder()
    let runtime = try RuntimeProcess(
      runtimePath: runtimePath,
      widgetsDirectoryURL: widgetsDirectoryURL,
      recorder: recorder,
      decoder: decoder,
      environment: try luaRuntimeEnvironment(for: widgetsDirectoryURL),
      autoRespondToCommands: false
    )
    defer { runtime.stop() }

    try runtime.sendHostEvent("{\"name\":\"forced\"}\n")
    let request = try await nextCommandRequest(
      from: recorder,
      matching: { $0.arguments != nil }
    )
    XCTAssertEqual(request.arguments, ["printf", "%s", "$HOME; echo unsafe"])
    XCTAssertFalse(request.isSynchronous)

    try runtime.sendCommandResponse(token: request.token, output: "literal", status: 0)
    let update = try await nextTreeUpdate(
      from: recorder,
      matching: { [self] in rootNode(in: $0)?.text == "literal:0" }
    )
    XCTAssertEqual(rootNode(in: update)?.text, "literal:0")
  }

  func testAfterEmitsTimerRequestAndRunsCallbackWhenFired() async throws {
    let widgetsDirectoryURL = try makeWidgetsDirectory()
    try """
    easybar.add("item", "timer", { position = "right", label = "waiting" })
    easybar.subscribe("timer", { easybar.events.forced }, function()
      easybar.after(2.5, function()
        easybar.set("timer", { label = "fired" })
      end)
    end)
    """.write(
      to: widgetsDirectoryURL.appendingPathComponent("timer.lua"),
      atomically: true,
      encoding: .utf8
    )

    let runtimeController = LuaProcessController(
      logger: ProcessLogger(label: "lua.after.test", minimumLevel: .error)
    )
    let runtimePath = try XCTUnwrap(runtimeController.resolvedRuntimePath())
    let recorder = RuntimeUpdateRecorder()
    let runtime = try RuntimeProcess(
      runtimePath: runtimePath,
      widgetsDirectoryURL: widgetsDirectoryURL,
      recorder: recorder,
      decoder: decoder,
      environment: try luaRuntimeEnvironment(for: widgetsDirectoryURL),
      autoRespondToCommands: false
    )
    defer { runtime.stop() }

    try runtime.sendHostEvent("{\"name\":\"forced\"}\n")
    let request = try await nextUpdate(from: recorder) {
      $0.type == .timerRequest
    }
    XCTAssertEqual(request.delaySeconds, 2.5)
    let token = try XCTUnwrap(request.token)

    try runtime.sendHostEvent(
      "{\"protocol_version\":1,\"type\":\"timer_fired\",\"token\":\"\(token)\"}\n"
    )
    let update = try await nextTreeUpdate(
      from: recorder,
      matching: { [self] in rootNode(in: $0)?.text == "fired" }
    )
    XCTAssertEqual(rootNode(in: update)?.text, "fired")
  }

  func testAfterHandleCancelsPendingTimer() async throws {
    let widgetsDirectoryURL = try makeWidgetsDirectory()
    try """
    easybar.add("item", "timer", { position = "right", label = "waiting" })
    easybar.subscribe("timer", { easybar.events.forced }, function()
      local timer = easybar.after(10, function()
        easybar.set("timer", { label = "unexpected" })
      end)
      timer:cancel()
    end)
    """.write(
      to: widgetsDirectoryURL.appendingPathComponent("timer-cancel.lua"),
      atomically: true,
      encoding: .utf8
    )

    let runtimeController = LuaProcessController(
      logger: ProcessLogger(label: "lua.after-cancel.test", minimumLevel: .error)
    )
    let runtimePath = try XCTUnwrap(runtimeController.resolvedRuntimePath())
    let recorder = RuntimeUpdateRecorder()
    let runtime = try RuntimeProcess(
      runtimePath: runtimePath,
      widgetsDirectoryURL: widgetsDirectoryURL,
      recorder: recorder,
      decoder: decoder,
      environment: try luaRuntimeEnvironment(for: widgetsDirectoryURL),
      autoRespondToCommands: false
    )
    defer { runtime.stop() }

    try runtime.sendHostEvent("{\"name\":\"forced\"}\n")
    let request = try await nextUpdate(from: recorder) { $0.type == .timerRequest }
    let token = try XCTUnwrap(request.token)
    let cancellation = try await nextUpdate(from: recorder) {
      $0.timerCancelToken == token
    }
    XCTAssertEqual(cancellation.timerCancelToken, token)

    try runtime.sendHostEvent(
      "{\"protocol_version\":1,\"type\":\"timer_fired\",\"token\":\"\(token)\"}\n"
    )
    try await expectNoUpdate(from: recorder) { [self] in
      rootNode(in: $0)?.text == "unexpected"
    }
  }

}
