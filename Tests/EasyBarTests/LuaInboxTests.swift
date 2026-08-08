import EasyBarShared
import Foundation
import XCTest

@testable import EasyBarApp

final class LuaInboxTests: LuaRenderRuntimeTestCase, @unchecked Sendable {
  func testPublishesClearsAndHandlesInboxActions() async throws {
    let widgetsDirectoryURL = try makeWidgetsDirectory()
    try """
    local status = easybar.add(easybar.kind.item, "inbox_test", {
      position = "right",
      label = "idle",
    })

    assert(not pcall(easybar.inbox.replace, "gitlab", { item = { id = "one" } }))
    assert(not pcall(easybar.inbox.replace, "gitlab", easybar.json.object()))
    assert(not pcall(easybar.inbox.configure, "gitlab", {
      actions = { refresh = { id = "refresh", title = "Refresh" } },
    }))
    assert(not pcall(easybar.inbox.configure, "gitlab", {
      order = 1.5,
      actions = {},
    }))

    easybar.inbox.on_action("  gitlab ", function(event)
      status:set({ label = event.target_widget_id .. ":" .. event.action_id })
    end)

    easybar.inbox.on_context_action(" gitlab  ", function(event)
      status:set({ label = "context:" .. event.action_id })
    end)

    easybar.inbox.configure(" gitlab ", {
      order = 20,
      actions = { { id = "sync", title = "Refresh", include_in_refresh_all = true } },
    })

    easybar.inbox.replace("  gitlab  ", {
      {
        id = "mr-42",
        title = "Review merge request",
        body = "**Pipeline passed**",
        format = "markdown",
        timestamp = 123,
        category = "Reviews",
        severity = "success",
        source = {
          name = "GitLab",
          icon = "GL",
          color = "#FC6D26",
          order = 20,
        },
        actions = { { id = "open", title = "Open" } },
      },
    })
    """.write(
      to: widgetsDirectoryURL.appendingPathComponent("inbox.lua"),
      atomically: true,
      encoding: .utf8
    )

    let runtimeController = LuaProcessController(
      logger: ProcessLogger(label: "lua.inbox.test", minimumLevel: .error)
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

    let replacement = try await nextUpdate(from: recorder) {
      $0.inboxReplacePayload?.source == "gitlab"
    }
    XCTAssertEqual(replacement.inboxReplacePayload?.items.first?.id, "mr-42")
    XCTAssertEqual(replacement.inboxReplacePayload?.items.first?.source?.name, "GitLab")
    XCTAssertEqual(replacement.inboxReplacePayload?.items.first?.source?.icon, "GL")
    XCTAssertEqual(replacement.inboxReplacePayload?.items.first?.source?.color, "#FC6D26")
    XCTAssertEqual(replacement.inboxReplacePayload?.items.first?.source?.order, 20)

    let configuration = try await nextUpdate(from: recorder) {
      $0.inboxConfigurationPayload?.source == "gitlab"
    }
    XCTAssertEqual(configuration.inboxConfigurationPayload?.actions.first?.id, "sync")
    XCTAssertEqual(configuration.inboxConfigurationPayload?.order, 20)
    XCTAssertTrue(
      configuration.inboxConfigurationPayload?.actions.first?.isIncludedInRefreshAll == true
    )

    try runtime.sendHostEvent(
      #"{"name":"inbox.action","widget_id":"builtin_inbox","target_widget_id":"mr-42","source":"gitlab","action_id":"open"}"#
        + "\n"
    )

    let actionUpdate = try await nextTreeUpdate(from: recorder) { [self] in
      rootNode(in: $0)?.text == "mr-42:open"
    }
    XCTAssertEqual(rootNode(in: actionUpdate)?.text, "mr-42:open")

    try runtime.sendHostEvent(
      #"{"name":"inbox.context_action","widget_id":"builtin_inbox","source":"gitlab","action_id":"sync"}"#
        + "\n"
    )

    let contextActionUpdate = try await nextTreeUpdate(from: recorder) { [self] in
      rootNode(in: $0)?.text == "context:sync"
    }
    XCTAssertEqual(rootNode(in: contextActionUpdate)?.text, "context:sync")
  }
}
