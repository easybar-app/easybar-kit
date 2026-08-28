import EasyBarShared
import Foundation
import XCTest

@testable import EasyBarKit

final class LuaPackageReloadTests: LuaRenderRuntimeTestCase, @unchecked Sendable {
  func testForcedRefreshAppliesPendingTargetedPackageReload() async throws {
    let widgets = try makeWidgetsDirectory()
    let packages = tempDirectoryURL.appendingPathComponent("managed-packages", isDirectory: true)
    let active = packages.appendingPathComponent("active", isDirectory: true)
    let sharedActive = active.appendingPathComponent("shared", isDirectory: true)
    let sharedV1 = packages.appendingPathComponent("store/shared/1.0.0", isDirectory: true)
    let sharedV2 = packages.appendingPathComponent("store/shared/2.0.0", isDirectory: true)
    let consumerV1 = packages.appendingPathComponent("store/consumer/1.0.0", isDirectory: true)
    let otherV1 = packages.appendingPathComponent("store/other/1.0.0", isDirectory: true)

    for directory in [sharedActive, sharedV1, sharedV2, consumerV1, otherV1] {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    try "return { value = 'old' }\n".write(
      to: sharedV1.appendingPathComponent("value.lua"),
      atomically: true,
      encoding: .utf8
    )
    try "return { value = 'new' }\n".write(
      to: sharedV2.appendingPathComponent("value.lua"),
      atomically: true,
      encoding: .utf8
    )
    try """
    local value = require("value")
    easybar.add(easybar.kind.item, "consumer", { label = value.value })
    """.write(
      to: consumerV1.appendingPathComponent("widget.lua"),
      atomically: true,
      encoding: .utf8
    )
    try """
    local other = easybar.add(easybar.kind.item, "other", { label = "stable" })
    other:subscribe(easybar.events.forced, function()
      other:set({ label = "forced" })
    end)
    """.write(
      to: otherV1.appendingPathComponent("widget.lua"),
      atomically: true,
      encoding: .utf8
    )

    try FileManager.default.createSymbolicLink(
      atPath: active.appendingPathComponent("consumer").path,
      withDestinationPath: "../store/consumer/1.0.0/widget.lua"
    )
    try FileManager.default.createSymbolicLink(
      atPath: active.appendingPathComponent("other").path,
      withDestinationPath: "../store/other/1.0.0/widget.lua"
    )
    let activeModule = sharedActive.appendingPathComponent("value.lua")
    try FileManager.default.createSymbolicLink(
      atPath: activeModule.path,
      withDestinationPath: "../../store/shared/1.0.0/value.lua"
    )

    let controller = LuaProcessController(
      logger: ProcessLogger(label: "lua.package-reload.test", minimumLevel: .error)
    )
    let runtimePath = try XCTUnwrap(controller.resolvedRuntimePath())
    let recorder = RuntimeUpdateRecorder()
    var environment = try luaRuntimeEnvironment(for: widgets)
    environment[SharedEnvironmentKeys.luaWidgetPackagesDirectory] = active.path
    let runtime = try RuntimeProcess(
      runtimePath: runtimePath,
      widgetsDirectoryURL: widgets,
      recorder: recorder,
      decoder: decoder,
      environment: environment,
      autoRespondToCommands: true
    )
    defer { runtime.stop() }

    let subscriptions = try await nextUpdate(from: recorder) { update in
      update.type == .subscriptions
    }
    XCTAssertTrue(subscriptions.subscribedEvents.contains("forced"))

    let initial = try await nextTreeUpdate(from: recorder) { [self] update in
      rootNode(in: update)?.id == "consumer"
    }
    XCTAssertEqual(rootNode(in: initial)?.text, "old")

    try FileManager.default.removeItem(at: activeModule)
    try FileManager.default.createSymbolicLink(
      atPath: activeModule.path,
      withDestinationPath: "../../store/shared/2.0.0/value.lua"
    )
    try """
    {"packages":["shared","consumer"],"modules":["value"],"widgets":["consumer"]}
    """.write(
      to: packages.appendingPathComponent(".reload-plan.json"),
      atomically: true,
      encoding: .utf8
    )

    try runtime.sendHostEvent("{\"name\":\"forced\"}\n")

    let cleared = try await nextUpdate(from: recorder) {
      $0.type == .clearRoot && $0.clearRootID == "consumer"
    }
    XCTAssertEqual(cleared.clearRootID, "consumer")

    let reloaded = try await nextTreeUpdate(from: recorder) { [self] update in
      rootNode(in: update)?.id == "consumer" && rootNode(in: update)?.text == "new"
    }
    XCTAssertEqual(rootNode(in: reloaded)?.text, "new")

    try await expectNoUpdate(from: recorder) { [self] update in
      update.type == .clearRoot && update.clearRootID == "other"
        || (rootNode(in: update)?.id == "other" && rootNode(in: update)?.text == "forced")
    }
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: packages.appendingPathComponent(".reload-plan.json").path)
    )
  }
}
