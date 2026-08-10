import EasyBarShared
import Foundation
import XCTest

@testable import EasyBarKit

final class LuaRenderStorageTests: LuaRenderRuntimeTestCase, @unchecked Sendable {
  func testStorageGetDefaultAndSetRoundTripThroughRuntimeProtocol() async throws {
    let widgetsDirectoryURL = try makeWidgetsDirectory()
    try """
    local initial = easybar.storage.get("storage-test", "method", "squash")
    local ok, err = easybar.storage.set("storage-test", "method", "rebase")
    assert(ok, err)
    local stored = easybar.storage.get("storage-test", "method")

    easybar.add(easybar.kind.item, "storage", {
        position = "right",
        label = initial .. ":" .. stored,
    })
    """.write(
      to: widgetsDirectoryURL.appendingPathComponent("storage-test.lua"),
      atomically: true,
      encoding: .utf8
    )

    let runtimeController = LuaProcessController(
      logger: ProcessLogger(label: "lua.storage.test", minimumLevel: .error)
    )
    let runtimePath = try XCTUnwrap(runtimeController.resolvedRuntimePath())
    let recorder = RuntimeUpdateRecorder()
    let runtime = try RuntimeProcess(
      runtimePath: runtimePath,
      widgetsDirectoryURL: widgetsDirectoryURL,
      recorder: recorder,
      decoder: decoder,
      environment: try luaRuntimeEnvironment(for: widgetsDirectoryURL),
      autoRespondToCommands: true
    )
    defer { runtime.stop() }

    let update = try await nextTreeUpdate(
      from: recorder,
      matching: { [self] in rootNode(in: $0)?.text == "squash:rebase" }
    )
    XCTAssertEqual(rootNode(in: update)?.text, "squash:rebase")
  }
}
