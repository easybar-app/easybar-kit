import EasyBarShared
import Foundation
import XCTest

@testable import EasyBarApp

final class LuaWidgetLibraryTests: LuaRenderRuntimeTestCase, @unchecked Sendable {
  func testRuntimeLoadsManagedPackagesSeparatelyFromManualWidgets() async throws {
    let widgets = try makeWidgetsDirectory()
    let activePackages = tempDirectoryURL.appendingPathComponent(
      "managed-packages/active",
      isDirectory: true
    )
    try FileManager.default.createDirectory(
      at: activePackages.appendingPathComponent("shared", isDirectory: true),
      withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
      at: activePackages.appendingPathComponent("managed-clock", isDirectory: true),
      withIntermediateDirectories: true
    )
    try "return { label = 'managed' }\n".write(
      to: activePackages.appendingPathComponent("shared/retry.lua"),
      atomically: true,
      encoding: .utf8
    )
    try """
    local retry = require("retry")
    easybar.add(easybar.kind.item, "managed_clock", { label = retry.label })
    """.write(
      to: activePackages.appendingPathComponent("managed-clock/widget.lua"),
      atomically: true,
      encoding: .utf8
    )
    try """
    easybar.add(easybar.kind.item, "manual_clock", { label = "manual" })
    """.write(
      to: widgets.appendingPathComponent("manual.lua"),
      atomically: true,
      encoding: .utf8
    )

    let logger = ProcessLogger(label: "lua.widget-library.test", minimumLevel: .error)
    let controller = LuaProcessController(logger: logger)
    let runtimePath = try XCTUnwrap(controller.resolvedRuntimePath())
    let recorder = RuntimeUpdateRecorder()
    var environment = try luaRuntimeEnvironment(for: widgets)
    environment[SharedEnvironmentKeys.luaWidgetPackagesDirectory] = activePackages.path
    let runtime = try RuntimeProcess(
      runtimePath: runtimePath,
      widgetsDirectoryURL: widgets,
      recorder: recorder,
      decoder: decoder,
      environment: environment,
      autoRespondToCommands: true
    )
    defer { runtime.stop() }

    let managedUpdate = try await nextTreeUpdate(from: recorder) { update in
      update.treePayload?.nodes.contains(where: { $0.id == "managed_clock" }) == true
    }
    let manualUpdate = try await nextTreeUpdate(from: recorder) { update in
      update.treePayload?.nodes.contains(where: { $0.id == "manual_clock" }) == true
    }
    XCTAssertEqual(
      managedUpdate.treePayload?.nodes.first(where: { $0.id == "managed_clock" })?.text,
      "managed"
    )
    XCTAssertEqual(
      manualUpdate.treePayload?.nodes.first(where: { $0.id == "manual_clock" })?.text,
      "manual"
    )
  }

  func testWidgetCanRequireDirectAndPackageModulesFromLibDirectory() async throws {
    let widgets = try makeWidgetsDirectory()
    let library = widgets.appendingPathComponent("lib", isDirectory: true)
    let packageDirectory = library.appendingPathComponent("format", isDirectory: true)
    try FileManager.default.createDirectory(
      at: packageDirectory,
      withIntermediateDirectories: true
    )

    try "return { value = 'direct' }\n".write(
      to: library.appendingPathComponent("direct.lua"),
      atomically: true,
      encoding: .utf8
    )
    try "return { value = 'package' }\n".write(
      to: packageDirectory.appendingPathComponent("init.lua"),
      atomically: true,
      encoding: .utf8
    )

    let node = try await renderWidget(
      """
      local direct = require("direct")
      local format = require("format")

      easybar.add("item", "module_test", {
        label = direct.value .. ":" .. format.value,
      })
      """,
      rootID: "module_test",
      in: widgets
    )

    XCTAssertEqual(node.text, "direct:package")
  }

  func testWidgetLibraryModulesAreCachedByRequire() async throws {
    let widgets = try makeWidgetsDirectory()
    let library = widgets.appendingPathComponent("lib", isDirectory: true)
    try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)

    try "return { token = {} }\n".write(
      to: library.appendingPathComponent("cached.lua"),
      atomically: true,
      encoding: .utf8
    )

    let node = try await renderWidget(
      """
      local first = require("cached")
      local second = require("cached")
      easybar.add("item", "cache_test", { label = tostring(first == second) })
      """,
      rootID: "cache_test",
      in: widgets
    )

    XCTAssertEqual(node.text, "true")
  }

  func testLuaRuntimeDiscoversUserWidgetsButNotModuleOrPackageRoots() async throws {
    let widgets = try makeWidgetsDirectory()
    let discoveredFiles = [
      ("clock.lua", "discovery_root"),
      (".hidden.lua", "discovery_hidden"),
      ("assets/preview.lua", "discovery_assets"),
      ("inbox/github/status.lua", "discovery_inbox"),
      ("simple/toggle.lua", "discovery_simple"),
    ]
    let excludedFiles = [
      "lib/compat.LUA",
      "shared/helper.lua",
      ".easybar/packages/example/widget.lua",
    ]

    for (relativePath, rootID) in discoveredFiles {
      let fileURL = widgets.appendingPathComponent(relativePath)
      try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try "easybar.add(easybar.kind.item, \"\(rootID)\", { label = \"\(rootID)\" })\n".write(
        to: fileURL,
        atomically: true,
        encoding: .utf8
      )
    }

    for relativePath in excludedFiles {
      let fileURL = widgets.appendingPathComponent(relativePath)
      try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try "error(\"module or package metadata executed\")\n".write(
        to: fileURL,
        atomically: true,
        encoding: .utf8
      )
    }

    try "error(\"non-Lua file executed\")\n".write(
      to: widgets.appendingPathComponent("ignored.txt"),
      atomically: true,
      encoding: .utf8
    )

    let logger = ProcessLogger(label: "lua.widget-library.test", minimumLevel: .error)
    let controller = LuaProcessController(logger: logger)
    let runtimePath = try XCTUnwrap(controller.resolvedRuntimePath())
    let recorder = RuntimeUpdateRecorder()
    let runtime = try RuntimeProcess(
      runtimePath: runtimePath,
      widgetsDirectoryURL: widgets,
      recorder: recorder,
      decoder: decoder,
      environment: try luaRuntimeEnvironment(for: widgets),
      autoRespondToCommands: true
    )
    defer { runtime.stop() }

    for (_, rootID) in discoveredFiles {
      let update = try await nextTreeUpdate(from: recorder) { update in
        update.treePayload?.nodes.contains(where: { $0.id == rootID }) == true
      }
      let node = try XCTUnwrap(update.treePayload?.nodes.first(where: { $0.id == rootID }))
      XCTAssertEqual(node.text, rootID)
    }
  }

  private func renderWidget(
    _ source: String,
    rootID: String,
    in widgetsDirectoryURL: URL
  ) async throws -> WidgetNodeState {
    let widgetFile = "widget.lua"
    try source.write(
      to: widgetsDirectoryURL.appendingPathComponent(widgetFile),
      atomically: true,
      encoding: .utf8
    )

    let logger = ProcessLogger(label: "lua.widget-library.test", minimumLevel: .error)
    let controller = LuaProcessController(logger: logger)
    let runtimePath = try XCTUnwrap(controller.resolvedRuntimePath())
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

    let update = try await nextTreeUpdate(from: recorder) { update in
      update.treePayload?.nodes.contains(where: { $0.id == rootID }) == true
    }

    return try XCTUnwrap(update.treePayload?.nodes.first(where: { $0.id == rootID }))
  }
}
