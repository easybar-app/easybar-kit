import EasyBarShared
import XCTest

@testable import EasyBarCtl

final class CLIArgumentsTests: XCTestCase {

  func testCommandCatalogPathsAreUnique() {
    let paths = CLI.commands.map { $0.path.joined(separator: " ") }
    XCTAssertEqual(Set(paths).count, paths.count)
  }

  func testEveryRootCommandGroupHasAtLeastOneCommand() {
    for group in CLI.commandGroups {
      XCTAssertTrue(
        CLI.commands.contains(where: { $0.path.first == group.name }),
        "Missing command for root group \(group.name)"
      )
    }
  }

  func testTopLevelRuntimeCommandsMapToSharedIPCCommands() throws {
    XCTAssertEqual(try parseArguments(["easybar", "refresh"]).action, .control(.manualRefresh))
    XCTAssertEqual(
      try parseArguments(["easybar", "config", "reload"]).action,
      .control(.reloadConfig)
    )
    XCTAssertEqual(
      try parseArguments(["easybar", "runtime", "restart"]).action,
      .control(.restartLuaRuntime)
    )
  }

  func testMetricsParsesSnapshotAndWatchModes() throws {
    XCTAssertEqual(try parseArguments(["easybar", "metrics"]).action, .metrics(watch: false))
    XCTAssertEqual(
      try parseArguments(["easybar", "metrics", "--watch"]).action,
      .metrics(watch: true)
    )
    XCTAssertEqual(
      try parseArguments(["easybar", "metrics", "-w"]).action,
      .metrics(watch: true)
    )
  }

  func testConfigValidateParsesOptionalPath() throws {
    XCTAssertEqual(
      try parseArguments(["easybar", "config", "validate"]).action,
      .validateConfig(configPath: nil)
    )
    XCTAssertEqual(
      try parseArguments([
        "easybar", "config", "validate", "--config", "/tmp/easybar.toml",
      ]).action,
      .validateConfig(configPath: "/tmp/easybar.toml")
    )
  }

  func testWidgetPackageInstallParsesRegistryAndDirectSourceOptions() throws {
    let registry = try parseArguments([
      "easybar", "widgets", "install", "caffeinate",
    ])
    XCTAssertEqual(
      registry.action,
      .installWidgetPackage(
        WidgetPackageInstallOptions(
          source: "caffeinate",
          sha256: nil,
          registry: nil,
          useRegistry: true
        )
      )
    )

    let local = try parseArguments([
      "easybar", "widgets", "install", "./my-widget",
      "--sha256", "abc",
      "--no-registry",
    ])
    XCTAssertEqual(
      local.action,
      .installWidgetPackage(
        WidgetPackageInstallOptions(
          source: "./my-widget",
          sha256: "abc",
          registry: nil,
          useRegistry: false
        )
      )
    )
  }

  func testWidgetPackageInstallRejectsAmbiguousOptions() {
    XCTAssertThrowsError(try parseArguments(["easybar", "widgets", "install"]))
    XCTAssertThrowsError(
      try parseArguments([
        "easybar", "widgets", "install", "caffeinate", "github",
      ])
    )
    XCTAssertThrowsError(
      try parseArguments([
        "easybar", "widgets", "install", "./widget",
        "--registry", "index.json", "--no-registry",
      ])
    )
    XCTAssertThrowsError(
      try parseArguments([
        "easybar", "widgets", "install", "./widget", "--socket", "/tmp/app.sock",
      ])
    )
    XCTAssertThrowsError(
      try parseArguments([
        "easybar", "widgets", "install", "./widget", "--widgets-dir", "/tmp/widgets",
      ])
    )
  }

  func testWidgetPackageSearchParsesOptionalQueryAndRegistry() throws {
    XCTAssertEqual(
      try parseArguments(["easybar", "widgets", "search"]).action,
      .searchWidgetPackages(WidgetPackageSearchOptions(query: nil, registry: nil))
    )
    XCTAssertEqual(
      try parseArguments([
        "easybar", "widgets", "search", "network", "--registry", "index.json",
      ]).action,
      .searchWidgetPackages(
        WidgetPackageSearchOptions(query: "network", registry: "index.json")
      )
    )
  }

  func testWidgetPackageSearchRejectsAmbiguousArguments() {
    XCTAssertThrowsError(
      try parseArguments(["easybar", "widgets", "search", "network", "system"])
    )
    XCTAssertThrowsError(
      try parseArguments([
        "easybar", "widgets", "search", "--socket", "/tmp/app.sock",
      ])
    )
  }

  func testWidgetPackageUninstallParsesOnePackageName() throws {
    XCTAssertEqual(
      try parseArguments(["easybar", "widgets", "uninstall", "caffeinate"]).action,
      .uninstallWidgetPackage("caffeinate")
    )
  }

  func testWidgetPackageUninstallRejectsAmbiguousArguments() {
    XCTAssertThrowsError(try parseArguments(["easybar", "widgets", "uninstall"]))
    XCTAssertThrowsError(
      try parseArguments([
        "easybar", "widgets", "uninstall", "caffeinate", "shared",
      ])
    )
    XCTAssertThrowsError(
      try parseArguments([
        "easybar", "widgets", "uninstall", "caffeinate", "--socket", "/tmp/app.sock",
      ])
    )
  }

  func testAgentRestartTargetsParse() throws {
    XCTAssertEqual(
      try parseArguments(["easybar", "agent", "restart", "calendar"]).action,
      .restartAgent(.calendar)
    )
    XCTAssertEqual(
      try parseArguments(["easybar", "agent", "restart", "network"]).action,
      .restartAgent(.network)
    )
    XCTAssertEqual(
      try parseArguments(["easybar", "agent", "restart", "all"]).action,
      .restartAgent(.all)
    )
  }

  func testAgentVersionTargetsAndJSONParse() throws {
    XCTAssertEqual(
      try parseArguments(["easybar", "agent", "version", "calendar"]).action,
      .versionAgent(.calendar, json: false)
    )
    XCTAssertEqual(
      try parseArguments(["easybar", "agent", "version", "network", "--json"]).action,
      .versionAgent(.network, json: true)
    )
    XCTAssertEqual(
      try parseArguments(["easybar", "agent", "version", "all"]).action,
      .versionAgent(.all, json: false)
    )
  }

  func testEventEmitMapsPublicNameToSharedIPCCommand() throws {
    XCTAssertEqual(
      try parseArguments(["easybar", "event", "emit", "workspace-change"]).action,
      .control(.workspaceChange)
    )
    XCTAssertThrowsError(
      try parseArguments(["easybar", "event", "emit", "unknown-event"])
    )
  }

  func testLogsDefaultsToRecentHistoryWithoutFollowing() throws {
    let parsed = try parseArguments(["easybar", "logs"])

    guard case .logs(let options) = parsed.action else {
      return XCTFail("Expected logs action")
    }
    XCTAssertEqual(options.historyLimit, 100)
    XCTAssertFalse(options.follow)
    XCTAssertFalse(options.json)
  }

  func testLogsParsesComposableFiltersAndExplicitFollow() throws {
    let parsed = try parseArguments([
      "easybar",
      "logs",
      "--widget",
      "tailscale",
      "--runtime=app",
      "--level",
      "debug",
      "--since",
      "30m",
      "--request-id",
      "lua-19",
      "--lines",
      "25",
      "--follow",
      "--json",
    ])

    guard case .logs(let options) = parsed.action else {
      return XCTFail("Expected logs action")
    }
    XCTAssertEqual(options.widget, "tailscale")
    XCTAssertEqual(options.runtime, .native)
    XCTAssertEqual(options.minimumLevel, .debug)
    XCTAssertEqual(options.since, "30m")
    XCTAssertEqual(options.requestID, "lua-19")
    XCTAssertEqual(options.historyLimit, 25)
    XCTAssertTrue(options.follow)
    XCTAssertTrue(options.json)
  }

  func testSinceAndRequestIDDefaultToAllRetainedHistory() throws {
    let since = try parseArguments(["easybar", "logs", "--since", "1h"])
    let request = try parseArguments(["easybar", "logs", "--request-id", "lua-19"])

    guard case .logs(let sinceOptions) = since.action,
      case .logs(let requestOptions) = request.action
    else {
      return XCTFail("Expected logs actions")
    }
    XCTAssertNil(sinceOptions.historyLimit)
    XCTAssertNil(requestOptions.historyLimit)
  }

  func testLogOptionsAreCommandLocal() {
    XCTAssertThrowsError(try parseArguments(["easybar", "refresh", "--since", "1h"]))
    XCTAssertThrowsError(try parseArguments(["easybar", "logs", "--all", "--lines", "10"]))
    XCTAssertThrowsError(try parseArguments(["easybar", "logs", "--no-follow"]))
  }

  func testInboxSendParsesStructuredMessage() throws {
    let parsed = try parseArguments([
      "easybar", "inbox", "send",
      "--source", "backup",
      "--id", "minio-nightly",
      "--severity", "error",
      "--title", "Backup failed",
      "--message", "The nightly backup failed.",
      "--category", "backup:minio",
      "--url", "https://grafana.example.com/backup-logs",
    ])

    guard case .inbox(.send(let item)) = parsed.action else {
      return XCTFail("Expected inbox send action")
    }
    XCTAssertEqual(item.source, "backup")
    XCTAssertEqual(item.id, "minio-nightly")
    XCTAssertEqual(item.severity, .error)
    XCTAssertEqual(item.title, "Backup failed")
    XCTAssertEqual(item.message, "The nightly backup failed.")
    XCTAssertEqual(item.group, "backup:minio")
    XCTAssertEqual(item.url, "https://grafana.example.com/backup-logs")
    XCTAssertTrue(item.unread)
  }

  func testInboxValuesThatLookLikeGlobalOptionsRemainValues() throws {
    let parsed = try parseArguments([
      "easybar", "inbox", "send", "--source", "test", "--title", "--debug",
      "--message", "--socket",
    ])

    guard case .inbox(.send(let item)) = parsed.action else {
      return XCTFail("Expected inbox send action")
    }
    XCTAssertEqual(item.title, "--debug")
    XCTAssertEqual(item.message, "--socket")
    XCTAssertFalse(parsed.debugEnabled)
    XCTAssertNil(parsed.socketPath)
  }

  func testInboxListAndMutationParsing() throws {
    let list = try parseArguments([
      "easybar", "inbox", "list", "--source", "backup", "--unread", "--json",
    ])
    XCTAssertEqual(
      list.action,
      .inbox(.list(source: "backup", unreadOnly: true, json: true))
    )

    let markRead = try parseArguments([
      "easybar", "inbox", "mark-read", "--source", "backup", "--id", "nightly",
    ])
    XCTAssertEqual(
      markRead.action,
      .inbox(.markRead(source: "backup", id: "nightly"))
    )

    let remove = try parseArguments([
      "easybar", "inbox", "remove", "--source", "backup", "--id", "nightly",
    ])
    XCTAssertEqual(remove.action, .inbox(.remove(source: "backup", id: "nightly")))
  }

  func testInboxDestructiveCommandsRequireUnambiguousScope() {
    XCTAssertThrowsError(try parseArguments(["easybar", "inbox", "dismiss"]))
    XCTAssertThrowsError(try parseArguments(["easybar", "inbox", "clear"]))
    XCTAssertThrowsError(
      try parseArguments(["easybar", "inbox", "remove", "--source", "backup"])
    )
    XCTAssertThrowsError(
      try parseArguments([
        "easybar", "inbox", "clear", "--source", "backup", "--all",
      ])
    )
    XCTAssertNoThrow(try parseArguments(["easybar", "inbox", "clear", "--all"]))
  }

  func testGlobalOptionsCanAppearBeforeOrAfterCommand() throws {
    let before = try parseArguments([
      "easybar", "--debug", "--socket", "/tmp/easybar.sock", "refresh",
    ])
    let after = try parseArguments([
      "easybar", "refresh", "--socket=/tmp/easybar.sock", "-d",
    ])

    XCTAssertEqual(before, after)
    XCTAssertEqual(before.socketPath, "/tmp/easybar.sock")
    XCTAssertTrue(before.debugEnabled)
  }

  func testSocketIsRejectedForCommandsThatDoNotUseOneSocket() {
    XCTAssertThrowsError(
      try parseArguments(["easybar", "logs", "--socket", "/tmp/easybar.sock"])
    )
    XCTAssertThrowsError(
      try parseArguments([
        "easybar", "agent", "restart", "all", "--socket", "/tmp/easybar.sock",
      ])
    )
    XCTAssertThrowsError(
      try parseArguments([
        "easybar", "agent", "version", "all", "--socket", "/tmp/easybar.sock",
      ])
    )
  }

  func testRemovedLegacySyntaxIsRejected() {
    XCTAssertThrowsError(try parseArguments(["easybar", "--refresh"]))
    XCTAssertThrowsError(try parseArguments(["easybar", "--metrics"]))
    XCTAssertThrowsError(try parseArguments(["easybar", "--validate-config"]))
    XCTAssertThrowsError(try parseArguments(["easybar", "inbox", "add"]))
    XCTAssertThrowsError(try parseArguments(["easybar", "inbox", "read"]))
    XCTAssertThrowsError(
      try parseArguments([
        "easybar", "inbox", "send", "--source", "backup", "--title", "Done",
        "--group", "storage",
      ])
    )
    XCTAssertThrowsError(
      try parseArguments(["easybar", "logs", "--runtime", "native"])
    )
  }

  func testHelpSelectsRootGroupAndCommandTopics() {
    XCTAssertThrowsError(try parseArguments(["easybar", "--help"])) { error in
      guard case AppError.showUsage(let topic) = error else {
        return XCTFail("Expected root usage")
      }
      XCTAssertEqual(topic, [])
    }

    XCTAssertThrowsError(try parseArguments(["easybar", "inbox", "--help"])) { error in
      guard case AppError.showUsage(let topic) = error else {
        return XCTFail("Expected inbox usage")
      }
      XCTAssertEqual(topic, ["inbox"])
    }

    XCTAssertThrowsError(try parseArguments(["easybar", "inbox", "send", "--help"])) { error in
      guard case AppError.showUsage(let topic) = error else {
        return XCTFail("Expected inbox send usage")
      }
      XCTAssertEqual(topic, ["inbox", "send"])
    }
  }
}
