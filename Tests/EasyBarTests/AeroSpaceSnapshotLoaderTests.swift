import Darwin
import Foundation
import XCTest

@testable import EasyBarKit
@testable import EasyBarShared

@MainActor
final class AeroSpaceSnapshotLoaderTests: XCTestCase {
  func testLoadParsesFormattedJSONWorkspaceAndWindowOutput() {
    let snapshot = loadSnapshot(
      jsonWorkspaces:
        """
        [
          {"workspace": "1", "workspace-is-focused": true, "workspace-is-visible": true},
          {"workspace": "2", "workspace-is-focused": false, "workspace-is-visible": false}
        ]
        """,
      jsonWindows:
        """
        [
          {
            "workspace": "1",
            "app-name": "Safari",
            "app-bundle-path": "/Applications/Safari.app"
          }
        ]
        """,
      jsonFocusedWindow:
        """
        [
          {
            "workspace": "1",
            "app-name": "Safari",
            "app-bundle-path": "/Applications/Safari.app",
            "window-layout": "h_tiles"
          }
        ]
        """
    )

    XCTAssertEqual(snapshot.spaces.map(\.name), ["1", "2"])
    XCTAssertEqual(snapshot.spaces.map(\.isFocused), [true, false])
    XCTAssertEqual(snapshot.spaces.map(\.isVisible), [true, false])
    XCTAssertEqual(snapshot.spaces[0].apps.map(\.name), ["Safari"])
    XCTAssertEqual(snapshot.spaces[0].apps.map(\.bundlePath), ["/Applications/Safari.app"])
    XCTAssertEqual(snapshot.focusedApp?.name, "Safari")
    XCTAssertEqual(snapshot.focusedApp?.bundlePath, "/Applications/Safari.app")
    XCTAssertEqual(snapshot.focusedLayoutMode, .hTiles)
  }

  func testLoadRejectsJSONWorkspaceFieldsThatAreMissing() {
    XCTAssertThrowsError(
      try AeroSpaceSnapshotLoader.loadSynchronously(
        run: { arguments in
          if arguments.first == "list-workspaces" {
            return #"[{"workspace":"1"}]"#
          }
          return "[]"
        },
        resolveAppID: { name, bundlePath in bundlePath ?? name }
      )
    )
  }

  func testLoadKeepsEmptyWorkspacesInSnapshot() {
    let snapshot = loadSnapshot(
      jsonWorkspaces:
        """
        [
          {"workspace": "1", "workspace-is-focused": true, "workspace-is-visible": true},
          {"workspace": "2", "workspace-is-focused": false, "workspace-is-visible": false}
        ]
        """,
      jsonWindows:
        """
        [
          {
            "workspace": "1",
            "app-name": "Safari",
            "app-bundle-path": "/Applications/Safari.app"
          }
        ]
        """,
      jsonFocusedWindow:
        """
        [
          {
            "workspace": "1",
            "app-name": "Safari",
            "app-bundle-path": "/Applications/Safari.app",
            "window-layout": "h_tiles"
          }
        ]
        """
    )

    XCTAssertEqual(snapshot.spaces.map(\.name), ["1", "2"])
    XCTAssertEqual(snapshot.spaces[0].apps.map(\.name), ["Safari"])
    XCTAssertEqual(snapshot.spaces[1].apps, [])
    XCTAssertEqual(snapshot.focusedApp?.name, "Safari")
    XCTAssertEqual(snapshot.focusedApp?.bundlePath, "/Applications/Safari.app")
    XCTAssertEqual(snapshot.focusedLayoutMode, .hTiles)
  }

  func testSpacesWidgetRequiresLabelsOrIcons() {
    XCTAssertFalse(SpacesWidgetView.hasVisibleContent(showLabel: false, showIcons: false))
    XCTAssertTrue(SpacesWidgetView.hasVisibleContent(showLabel: true, showIcons: false))
    XCTAssertTrue(SpacesWidgetView.hasVisibleContent(showLabel: false, showIcons: true))
    XCTAssertTrue(SpacesWidgetView.hasVisibleContent(showLabel: true, showIcons: true))
  }

  func testVisibleSpacesRespectsHideEmptyConfiguration() {
    let spaces = [
      SpaceItem(id: "1", name: "1", isFocused: false, isVisible: false, apps: []),
      SpaceItem(id: "2", name: "2", isFocused: true, isVisible: true, apps: []),
      SpaceItem(
        id: "3",
        name: "3",
        isFocused: false,
        isVisible: false,
        apps: [SpaceApp(id: "mail", bundleID: "", name: "Mail", bundlePath: nil)]
      ),
    ]

    XCTAssertEqual(
      visibleSpaceNames(
        spaces,
        hideEmpty: false,
        showLabel: true,
        showIcons: true,
        collapseInactive: false
      ),
      ["1", "2", "3"]
    )
    XCTAssertEqual(
      visibleSpaceNames(
        spaces,
        hideEmpty: true,
        showLabel: true,
        showIcons: true,
        collapseInactive: false
      ),
      ["2", "3"]
    )
  }

  func testVisibleSpacesFollowsContentAndCollapseMatrix() {
    let spaces = contentVisibilityTestSpaces()

    XCTAssertEqual(
      visibleSpaceNames(spaces, showLabel: true, showIcons: true, collapseInactive: false),
      ["1", "2", "3"]
    )
    XCTAssertEqual(
      visibleSpaceNames(spaces, showLabel: true, showIcons: true, collapseInactive: true),
      ["1", "2", "3"]
    )
    XCTAssertEqual(
      visibleSpaceNames(spaces, showLabel: true, showIcons: false, collapseInactive: false),
      ["1", "2", "3"]
    )
    XCTAssertEqual(
      visibleSpaceNames(spaces, showLabel: true, showIcons: false, collapseInactive: true),
      ["2"]
    )
    XCTAssertEqual(
      visibleSpaceNames(spaces, showLabel: false, showIcons: true, collapseInactive: false),
      ["1", "2", "3"]
    )
    XCTAssertEqual(
      visibleSpaceNames(spaces, showLabel: false, showIcons: true, collapseInactive: true),
      ["2"]
    )
    XCTAssertEqual(
      visibleSpaceNames(spaces, showLabel: false, showIcons: false, collapseInactive: false),
      []
    )
    XCTAssertEqual(
      visibleSpaceNames(spaces, showLabel: false, showIcons: false, collapseInactive: true),
      []
    )
  }

  func testVisibleSpacesOmitsInactiveSpacesWithoutRemainingContent() {
    let spaces = contentVisibilityTestSpaces()

    XCTAssertEqual(
      visibleSpaceNames(
        spaces,
        showLabel: true,
        showIcons: true,
        showOnlyFocusedLabel: true,
        collapseInactive: true
      ),
      ["2"]
    )
    XCTAssertEqual(
      visibleSpaceNames(
        spaces,
        showLabel: true,
        showIcons: false,
        showOnlyFocusedLabel: true,
        collapseInactive: false
      ),
      ["2"]
    )
  }

  func testLoadParsesWorkspaceNamesContainingSpaces() {
    let snapshot = loadSnapshot(
      jsonWorkspaces:
        """
        [
          {"workspace": "Work Inbox", "workspace-is-focused": false, "workspace-is-visible": true},
          {"workspace": "Deep Focus", "workspace-is-focused": true, "workspace-is-visible": true}
        ]
        """,
      jsonWindows: "[]",
      jsonFocusedWindow:
        """
        [
          {
            "workspace": "Deep Focus",
            "app-name": "Ghostty",
            "app-bundle-path": "/Applications/Ghostty.app",
            "window-layout": "floating"
          }
        ]
        """
    )

    XCTAssertEqual(snapshot.spaces.map(\.name), ["Work Inbox", "Deep Focus"])
    XCTAssertEqual(snapshot.spaces.map(\.isFocused), [false, true])
    XCTAssertEqual(snapshot.spaces.map(\.isVisible), [true, true])
    XCTAssertEqual(snapshot.focusedLayoutMode, .floating)
  }

  func testLoadDeduplicatesAppsByResolvedIdentity() {
    let snapshot = loadSnapshot(
      jsonWorkspaces:
        """
        [
          {"workspace": "1", "workspace-is-focused": true, "workspace-is-visible": true}
        ]
        """,
      jsonWindows:
        """
        [
          {
            "workspace": "1",
            "app-name": "Safari",
            "app-bundle-path": "/Applications/Safari.app"
          },
          {
            "workspace": "1",
            "app-name": "Safari",
            "app-bundle-path": "/Applications/Safari.app"
          },
          {
            "workspace": "1",
            "app-name": "Safari Technology Preview",
            "app-bundle-path": "/Applications/Safari Technology Preview.app"
          }
        ]
        """,
      jsonFocusedWindow: "[]"
    )

    XCTAssertEqual(
      snapshot.spaces[0].apps.map(\.name),
      ["Safari", "Safari Technology Preview"]
    )
    XCTAssertEqual(
      snapshot.spaces[0].apps.map(\.id),
      ["/Applications/Safari.app", "/Applications/Safari Technology Preview.app"]
    )
  }

  func testLoadUsesFormattedJSONCommandsOnly() throws {
    var requestedArguments: [[String]] = []

    _ = try AeroSpaceSnapshotLoader.loadSynchronously(
      run: { arguments in
        requestedArguments.append(arguments)
        switch arguments {
        case [
          "list-workspaces", "--all", "--json", "--format",
          "%{workspace} %{workspace-is-focused} %{workspace-is-visible}",
        ]:
          return
            """
            [
              {"workspace": "1", "workspace-is-focused": true, "workspace-is-visible": true}
            ]
            """
        case [
          "list-windows", "--all", "--json", "--format",
          "%{workspace} %{app-name} %{app-bundle-path}",
        ]:
          return "[]"
        case [
          "list-windows", "--focused", "--json", "--format",
          "%{workspace} %{app-name} %{app-bundle-path} %{window-layout}",
        ]:
          return "[]"
        default:
          return nil
        }
      },
      resolveAppID: { name, bundlePath in bundlePath ?? name }
    )

    XCTAssertEqual(
      requestedArguments,
      [
        [
          "list-workspaces", "--all", "--json", "--format",
          "%{workspace} %{workspace-is-focused} %{workspace-is-visible}",
        ],
        [
          "list-windows", "--all", "--json", "--format",
          "%{workspace} %{app-name} %{app-bundle-path}",
        ],
        [
          "list-windows", "--focused", "--json", "--format",
          "%{workspace} %{app-name} %{app-bundle-path} %{window-layout}",
        ],
      ]
    )
  }

  func testCommandRunnerResolvesAeroSpaceFromPathBeforeFallbacks() throws {
    let directoryURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("easybar-aerospace-path-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
      at: directoryURL,
      withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: directoryURL) }

    let executableURL = directoryURL.appendingPathComponent("aerospace")
    try "#!/usr/bin/env bash\nexit 0\n".write(
      to: executableURL,
      atomically: true,
      encoding: .utf8
    )
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755],
      ofItemAtPath: executableURL.path
    )

    XCTAssertEqual(
      AeroSpaceCommandRunner.defaultExecutablePath(environment: [
        SharedEnvironmentKeys.path: directoryURL.path
      ]),
      executableURL.path
    )
  }

  private func contentVisibilityTestSpaces() -> [SpaceItem] {
    return [
      SpaceItem(
        id: "1",
        name: "1",
        isFocused: false,
        isVisible: false,
        apps: [SpaceApp(id: "mail", bundleID: "", name: "Mail", bundlePath: nil)]
      ),
      SpaceItem(
        id: "2",
        name: "2",
        isFocused: true,
        isVisible: true,
        apps: [SpaceApp(id: "terminal", bundleID: "", name: "Terminal", bundlePath: nil)]
      ),
      SpaceItem(
        id: "3",
        name: "3",
        isFocused: false,
        isVisible: false,
        apps: [SpaceApp(id: "browser", bundleID: "", name: "Browser", bundlePath: nil)]
      ),
    ]
  }

  private func visibleSpaceNames(
    _ spaces: [SpaceItem],
    hideEmpty: Bool = false,
    showLabel: Bool,
    showIcons: Bool,
    showOnlyFocusedLabel: Bool = false,
    collapseInactive: Bool
  ) -> [String] {
    return SpacesWidgetView.visibleSpaces(
      spaces,
      hideEmpty: hideEmpty,
      showLabel: showLabel,
      showIcons: showIcons,
      showOnlyFocusedLabel: showOnlyFocusedLabel,
      collapseInactive: collapseInactive
    ).map(\.name)
  }

  private func loadSnapshot(
    jsonWorkspaces: String,
    jsonWindows: String,
    jsonFocusedWindow: String,
    resolveAppID: (String, String?) -> String = { name, bundlePath in bundlePath ?? name }
  ) -> AeroSpaceSnapshot {
    try! AeroSpaceSnapshotLoader.loadSynchronously(
      run: { arguments in
        switch arguments {
        case [
          "list-workspaces", "--all", "--json", "--format",
          "%{workspace} %{workspace-is-focused} %{workspace-is-visible}",
        ]:
          return jsonWorkspaces
        case [
          "list-windows", "--all", "--json", "--format",
          "%{workspace} %{app-name} %{app-bundle-path}",
        ]:
          return jsonWindows
        case [
          "list-windows", "--focused", "--json", "--format",
          "%{workspace} %{app-name} %{app-bundle-path} %{window-layout}",
        ]:
          return jsonFocusedWindow
        default:
          return nil
        }
      },
      resolveAppID: resolveAppID
    )
  }
}

final class AeroSpaceVersionRequirementTests: XCTestCase {
  func testValidateAcceptsSupportedClientAndServerVersions() throws {
    try AeroSpaceVersionRequirement.validate(
      output:
        """
        aerospace CLI client version: 0.21.1-Beta cfd4eab235b254ff5f1a1b9180a3997ae060162a
        AeroSpace.app server version: 0.21.0-Beta dd6b927a299c3af3e5760c4c3fc6012b984f9e51
        """
    )
  }

  func testValidateRejectsOldClientVersion() {
    XCTAssertThrowsError(
      try AeroSpaceVersionRequirement.validate(
        output:
          """
          aerospace CLI client version: 0.20.0-Beta cfd4eab235b254ff5f1a1b9180a3997ae060162a
          AeroSpace.app server version: 0.21.0-Beta dd6b927a299c3af3e5760c4c3fc6012b984f9e51
          """
      )
    )
  }

  func testValidateRejectsOldServerVersion() {
    XCTAssertThrowsError(
      try AeroSpaceVersionRequirement.validate(
        output:
          """
          aerospace CLI client version: 0.21.0-Beta cfd4eab235b254ff5f1a1b9180a3997ae060162a
          AeroSpace.app server version: 0.20.0-Beta dd6b927a299c3af3e5760c4c3fc6012b984f9e51
          """
      )
    )
  }

  func testValidateRejectsUnparseableVersionOutput() {
    XCTAssertThrowsError(try AeroSpaceVersionRequirement.validate(output: "AeroSpace unknown"))
  }
}

final class AeroSpaceCommandRunnerTests: XCTestCase {
  func testRunLogsStderrWhenCommandExitsNonZero() async throws {
    let directoryURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "easybar-aerospace-runner-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directoryURL) }

    let scriptURL = directoryURL.appendingPathComponent("aerospace")
    try """
    #!/bin/sh
    echo 'bad format token' >&2
    exit 2
    """.write(to: scriptURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755],
      ofItemAtPath: scriptURL.path
    )

    let logURL = directoryURL.appendingPathComponent("process.log")
    let logger = ProcessLogger(
      label: "easybar.app.services.aerospace.commands",
      minimumLevel: .debug,
      outputStream: nil,
      errorStream: nil
    )
    logger.configureFileLogging(enabled: true, path: logURL.path)
    defer { logger.configureFileLogging(enabled: false, path: "") }

    let runner = AeroSpaceCommandRunner(
      logger: logger,
      executablePathResolver: { scriptURL.path }
    )

    let outputValue = await runner.run(arguments: ["list-workspaces", "--all", "--json"])
    logger.configureFileLogging(enabled: false, path: "")

    XCTAssertNil(outputValue)

    let output = try String(contentsOf: logURL, encoding: .utf8)
    XCTAssertTrue(output.contains("aerospace command exited"))
    XCTAssertTrue(output.contains("status=2"))
    XCTAssertTrue(output.contains("stderr_bytes=16"))
  }

  func testRunCleansUpDescendantHoldingOutputPipes() async throws {
    let directoryURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "easybar-aerospace-descendant-tests-\(UUID().uuidString)",
        isDirectory: true
      )
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directoryURL) }

    let childPIDURL = directoryURL.appendingPathComponent("child.pid")
    let scriptURL = directoryURL.appendingPathComponent("aerospace")
    try """
    #!/bin/sh
    sleep 30 &
    echo "$!" > "\(childPIDURL.path)"
    printf 'ok'
    """.write(to: scriptURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755],
      ofItemAtPath: scriptURL.path
    )

    let runner = AeroSpaceCommandRunner(
      logger: ProcessLogger(
        label: "easybar.app.services.aerospace.commands",
        minimumLevel: .error,
        outputStream: nil,
        errorStream: nil
      ),
      executablePathResolver: { scriptURL.path },
      commandTimeout: 2
    )
    let startedAt = Date()

    let output = await runner.run(arguments: ["list-workspaces"])
    XCTAssertEqual(output, "ok")
    XCTAssertLessThan(Date().timeIntervalSince(startedAt), 2)

    let childPIDText = try String(contentsOf: childPIDURL, encoding: .utf8)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let childPID = try XCTUnwrap(Int32(childPIDText))
    XCTAssertTrue(waitUntilProcessIsAbsent(childPID))
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
