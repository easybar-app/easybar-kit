import EasyBarShared
import Foundation
import XCTest

@testable import EasyBarKit

final class LuaWidgetLibraryTests: LuaRenderRuntimeTestCase, @unchecked Sendable {
  func testRuntimeLoadsManagedPackagesSeparatelyFromManualWidgets() async throws {
    let widgets = try makeWidgetsDirectory()
    let managedPackages = tempDirectoryURL.appendingPathComponent(
      "managed-packages",
      isDirectory: true
    )
    let activePackages = managedPackages.appendingPathComponent("active", isDirectory: true)
    let versionDirectory = managedPackages.appendingPathComponent(
      "store/managed-clock/1.0.0",
      isDirectory: true
    )
    let assetsDirectory = versionDirectory.appendingPathComponent("assets", isDirectory: true)
    try FileManager.default.createDirectory(
      at: activePackages.appendingPathComponent("shared", isDirectory: true),
      withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(at: assetsDirectory, withIntermediateDirectories: true)
    try "return { label = 'managed' }\n".write(
      to: versionDirectory.appendingPathComponent("retry.lua"),
      atomically: true,
      encoding: .utf8
    )
    try "<svg/>\n".write(
      to: assetsDirectory.appendingPathComponent("icon.svg"),
      atomically: true,
      encoding: .utf8
    )
    try """
    local retry = require("retry")
    local relative_asset = easybar.asset("assets/icon.svg")
    local root_asset = easybar.asset("@/assets/icon.svg")
    easybar.add(easybar.kind.item, "managed_clock", {
      label = retry.label .. "|" .. relative_asset .. "|" .. root_asset,
    })
    """.write(
      to: versionDirectory.appendingPathComponent("widget.lua"),
      atomically: true,
      encoding: .utf8
    )
    try FileManager.default.createSymbolicLink(
      atPath: activePackages.appendingPathComponent("managed-clock", isDirectory: false).path,
      withDestinationPath: "../store/managed-clock/1.0.0/widget.lua"
    )
    try FileManager.default.createSymbolicLink(
      atPath: activePackages.appendingPathComponent("shared/retry.lua").path,
      withDestinationPath: "../../store/managed-clock/1.0.0/retry.lua"
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
    let assetPath = versionDirectory.appendingPathComponent("assets/icon.svg").path
    XCTAssertEqual(
      managedUpdate.treePayload?.nodes.first(where: { $0.id == "managed_clock" })?.text,
      "managed|\(assetPath)|\(assetPath)"
    )
    XCTAssertEqual(
      manualUpdate.treePayload?.nodes.first(where: { $0.id == "manual_clock" })?.text,
      "manual"
    )
  }

  func testWidgetCanRequireDirectAndPackageModulesFromSharedDirectory() async throws {
    let widgets = try makeWidgetsDirectory()
    let library = widgets.appendingPathComponent("shared", isDirectory: true)
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
    let library = widgets.appendingPathComponent("shared", isDirectory: true)
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

  func testLuaRuntimeDiscoversUserWidgetsButNotSharedModules() async throws {
    let widgets = try makeWidgetsDirectory()
    let discoveredFiles = [
      ("clock.lua", "discovery_root"),
      (".easybar/custom.lua", "discovery_dot_easybar"),
      (".hidden.lua", "discovery_hidden"),
      ("assets/preview.lua", "discovery_assets"),
      ("inbox/github/status.lua", "discovery_inbox"),
      ("simple/toggle.lua", "discovery_simple"),
    ]
    let excludedFiles = [
      "shared/helper.lua"
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
