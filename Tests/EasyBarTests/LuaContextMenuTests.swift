import EasyBarShared
import Foundation
import XCTest

@testable import EasyBarApp

final class LuaContextMenuTests: LuaRenderRuntimeTestCase, @unchecked Sendable {
  func testMenuRendersReplacesAndRemovesDynamically() async throws {
    let widgetsDirectoryURL = try makeWidgetsDirectory()
    try """
    local phase = 0
    local github = easybar.add("item", "github", {
      label = "GitHub",
      context_menu = {
        { id = "refresh", title = "Refresh" },
        { separator = true },
        { title = "Filter", submenu = {
          { id = "all", title = "All", checked = true },
        } },
        { id = "", title = "Invalid" },
        { id = "refresh", title = "Duplicate" },
      },
    })

    github:subscribe(easybar.events.forced, function()
      phase = phase + 1
      if phase == 1 then
        github:set({ context_menu = {
          { id = "open", title = "Open", enabled = false },
        } })
      else
        github:unset("context_menu")
      end
    end)

    github:subscribe(easybar.events.context_menu.clicked, function(event)
      github:set({ label = event.action_id })
    end)
    """.write(
      to: widgetsDirectoryURL.appendingPathComponent("github.lua"),
      atomically: true,
      encoding: .utf8
    )

    let logger = ProcessLogger(label: "lua.context-menu.test", minimumLevel: .error)
    let runtimeController = LuaProcessController(logger: logger)
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

    let initial = try await nextTreeUpdate(from: recorder) { update in
      self.rootNode(in: update)?.contextMenu?.first?.id == "refresh"
    }
    XCTAssertEqual(rootNode(in: initial)?.contextMenu?[2].submenu?.first?.id, "all")

    try runtime.sendHostEvent(
      "{\"name\":\"context_menu.clicked\",\"widget_id\":\"github\",\"target_widget_id\":\"github\",\"action_id\":\"refresh\"}\n"
    )
    let selected = try await nextTreeUpdate(from: recorder) { update in
      self.rootNode(in: update)?.text == "refresh"
    }
    XCTAssertEqual(rootNode(in: selected)?.text, "refresh")

    try runtime.sendHostEvent("{\"name\":\"forced\"}\n")
    let replaced = try await nextTreeUpdate(from: recorder) { update in
      self.rootNode(in: update)?.contextMenu?.first?.id == "open"
    }
    XCTAssertEqual(rootNode(in: replaced)?.contextMenu?.count, 1)
    XCTAssertFalse(rootNode(in: replaced)?.contextMenu?.first?.enabled ?? true)

    try runtime.sendHostEvent("{\"name\":\"forced\"}\n")
    let removed = try await nextTreeUpdate(from: recorder) { update in
      guard let root = self.rootNode(in: update) else { return false }
      return root.id == "github" && root.contextMenu == nil
    }
    XCTAssertNil(rootNode(in: removed)?.contextMenu)
  }
}
