import EasyBarShared
import Foundation
import XCTest

@testable import EasyBarApp
@testable import EasyBarCtl

final class LuaMetricsTests: XCTestCase {
  func testLogBridgeClassifiesStructuredLevelsAndRawStderr() {
    let bridge = LuaLogBridge(
      logger: ProcessLogger(
        label: "lua.metrics.tests",
        minimumLevel: .error,
        outputStream: nil,
        errorStream: nil
      )
    )

    assertStructured(
      bridge.handle("EASYBAR_LUA_LOG\tWARN\tgitlab-inbox\trefresh failed"),
      level: .warn
    )
    assertStructured(
      bridge.handle("EASYBAR_LUA_LOG\tERROR\truntime\tdecode failed"),
      level: .error
    )
    assertStructured(
      bridge.handle("EASYBAR_LUA_LOG\tUNKNOWN\truntime\tfallback"),
      level: .info
    )

    guard case .raw = bridge.handle("lua: runtime.lua:42: unexpected value") else {
      return XCTFail("Expected unstructured stderr to be classified as raw")
    }
  }

  func testLogBridgeTagsInfoWidgetLogsAsLuaWithoutSubsystemMetadata() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "easybar-lua-log-bridge-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let fileURL = directory.appendingPathComponent("easybar.out")
    let logger = ProcessLogger(
      label: "easybar.services.lua.transport.runtime",
      minimumLevel: .info,
      outputStream: nil,
      errorStream: nil
    )
    logger.configureFileLogging(enabled: true, path: fileURL.path)

    let bridge = LuaLogBridge(logger: logger)
    bridge.handle("EASYBAR_LUA_LOG\tINFO\tbrew-inbox\trefresh completed")
    logger.configureFileLogging(enabled: false, path: "")

    let line = try String(contentsOf: fileURL, encoding: .utf8)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let record = ProcessLogRecord.parse(line, source: "easybar")

    XCTAssertEqual(record.widget, "brew-inbox")
    XCTAssertEqual(record.runtime, .lua)
    XCTAssertEqual(record.fields["runtime"], ProcessLogRuntime.lua.rawValue)
    XCTAssertNil(record.fields["subsystem"])
  }

  func testMetricsCoordinatorSplitsLuaLogSeveritiesAndRawStderr() async {
    let coordinator = MetricsCoordinator()

    await coordinator.recordLuaSubscriptions(["system_woke", "focus_change"])
    await coordinator.recordLuaStderrLine(.structured(.debug))
    await coordinator.recordLuaStderrLine(.structured(.warn))
    await coordinator.recordLuaStderrLine(.structured(.error))
    await coordinator.recordLuaStderrLine(.raw)

    let runtime = await coordinator.snapshot().runtime

    XCTAssertEqual(runtime.subscribedEvents, ["focus_change", "system_woke"])
    XCTAssertEqual(runtime.stderrLines, 4)
    XCTAssertEqual(runtime.luaLogLines, 3)
    XCTAssertEqual(runtime.luaWarningLines, 1)
    XCTAssertEqual(runtime.luaErrorLines, 1)
    XCTAssertEqual(runtime.luaRawStderrLines, 1)
  }

  func testMetricsRendererUsesExplicitLuaAndWidgetTreeLabels() {
    let text = MetricsRenderer.snapshotText(
      snapshot(
        runtime: runtimeMetrics(
          subscribedEvents: [
            "focus_change",
            "interval_tick:github_inbox_timer:300",
            "system_woke",
          ],
          stderrLines: 10,
          luaLogLines: 8,
          luaWarningLines: 2,
          luaErrorLines: 1,
          luaRawStderrLines: 2
        )
      )
    )

    XCTAssertTrue(text.contains("lua_reads"))
    XCTAssertTrue(text.contains("lua_writes"))
    XCTAssertTrue(text.contains("lua_logs"))
    XCTAssertTrue(text.contains("lua_warn"))
    XCTAssertTrue(text.contains("lua_error"))
    XCTAssertTrue(text.contains("lua_raw_stderr"))
    XCTAssertTrue(text.contains("Subscribed events (3)"))
    XCTAssertTrue(text.contains("- focus_change"))
    XCTAssertTrue(text.contains("- github_inbox_timer (every 5m)"))
    XCTAssertTrue(text.contains("- system_woke"))
    XCTAssertFalse(text.contains("interval_tick:github_inbox_timer:300"))
    XCTAssertTrue(text.contains("Widget trees (top 8)"))
    XCTAssertTrue(text.contains("github_inbox_timer"))
    XCTAssertTrue(text.contains("Events (top 8)"))
    XCTAssertFalse(text.contains("transport/err"))
  }

  func testMetricsRendererFallsBackForLegacyStderrTotals() {
    let text = MetricsRenderer.snapshotText(
      snapshot(runtime: runtimeMetrics(stderrLines: 7))
    )

    XCTAssertTrue(text.contains("lua_stderr"))
    XCTAssertFalse(text.contains("lua_raw_stderr"))
  }

  func testWideWatchRendererUsesCompactSideBySideTiles() {
    let snapshot = snapshot(
      runtime: runtimeMetrics(
        subscribedEvents: [
          "forced",
          "interval_tick:github_inbox_timer:300",
          "system_woke",
        ],
        stderrLines: 10,
        luaLogLines: 8,
        luaWarningLines: 2,
        luaErrorLines: 1,
        luaRawStderrLines: 2
      )
    )
    var history = MetricsHistory(limit: 32)
    history.append(snapshot)

    let text = MetricsRenderer.watchText(snapshot, history: history, terminalWidth: 240)
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

    XCTAssertTrue(
      lines.contains { $0.hasPrefix("Runtime") && $0.contains("Lua") && $0.contains("Delivery") })
    XCTAssertTrue(
      lines.contains {
        $0.hasPrefix("Subscriptions (3)")
          && $0.contains("Widget trees (top 8)")
          && $0.contains("Events (top 8)")
      }
    )
    XCTAssertTrue(text.contains("github_inbox_timer (5m)"))
    XCTAssertTrue(text.contains("upd nodes    age"))
    XCTAssertTrue(text.contains("tot   rate drop coal"))
    XCTAssertFalse(text.contains("github_inbox_timer (every 5m)"))
    XCTAssertFalse(text.contains("last_tree"))
    XCTAssertLessThanOrEqual(lines.map(\.count).max() ?? 0, 119)
  }

  func testNarrowWatchRendererStacksCompactTiles() {
    let snapshot = snapshot(
      runtime: runtimeMetrics(
        subscribedEvents: ["forced", "system_woke"],
        stderrLines: 1,
        luaLogLines: 1,
        luaWarningLines: 0,
        luaErrorLines: 0,
        luaRawStderrLines: 0
      )
    )
    var history = MetricsHistory(limit: 32)
    history.append(snapshot)

    let text = MetricsRenderer.watchText(snapshot, history: history, terminalWidth: 80)
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

    XCTAssertTrue(lines.contains("Runtime"))
    XCTAssertTrue(lines.contains("Lua"))
    XCTAssertTrue(lines.contains("Delivery"))
    XCTAssertTrue(lines.contains("Subscriptions (2)"))
    XCTAssertTrue(lines.contains("Widget trees (top 8)"))
    XCTAssertTrue(lines.contains("Events (top 8)"))
    XCTAssertFalse(lines.contains { $0.hasPrefix("Runtime") && $0.contains("Delivery") })
  }

  func testMetricsRendererHandlesNonFiniteAndHugeIntervalDurations() {
    let value = snapshot(
      runtime: runtimeMetrics(
        subscribedEvents: [
          "interval_tick:infinite:inf",
          "interval_tick:huge:1e20",
        ],
        stderrLines: 0
      )
    )

    let text = MetricsRenderer.snapshotText(value)

    XCTAssertTrue(text.contains("- interval_tick:infinite:inf"))
    XCTAssertTrue(text.contains("- huge (every "))
    XCTAssertFalse(text.contains("interval_tick:huge:1e20"))
  }

  func testWatchRendererSanitizesNonFiniteSamples() {
    let value = snapshot(
      runtime: runtimeMetrics(
        stderrLines: 0,
        eventsPerSecond: .nan,
        treeUpdatesPerSecond: .infinity
      ),
      processCPUPercent: .nan,
      processResidentSizeBytes: UInt64.max
    )
    var history = MetricsHistory(limit: 32)
    history.append(value)

    let text = MetricsRenderer.watchText(value, history: history, terminalWidth: 120)
      .lowercased()

    XCTAssertFalse(text.contains("nan"))
    XCTAssertFalse(text.contains("inf"))
  }

  func testRuntimeMetricsDecodesPayloadWithoutLuaLogBreakdown() throws {
    let encoder = JSONEncoder()
    let encoded = try encoder.encode(runtimeMetrics(stderrLines: 7))
    guard var object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else {
      return XCTFail("Expected a runtime metrics JSON object")
    }

    object.removeValue(forKey: "luaLogLines")
    object.removeValue(forKey: "luaWarningLines")
    object.removeValue(forKey: "luaErrorLines")
    object.removeValue(forKey: "luaRawStderrLines")
    object.removeValue(forKey: "subscribedEvents")

    let legacyPayload = try JSONSerialization.data(withJSONObject: object)
    let decoded = try JSONDecoder().decode(IPC.RuntimeMetrics.self, from: legacyPayload)

    XCTAssertEqual(decoded.stderrLines, 7)
    XCTAssertNil(decoded.subscribedEvents)
    XCTAssertNil(decoded.luaLogLines)
    XCTAssertNil(decoded.luaWarningLines)
    XCTAssertNil(decoded.luaErrorLines)
    XCTAssertNil(decoded.luaRawStderrLines)
  }

  private func assertStructured(
    _ classification: LuaStderrLineClassification,
    level expectedLevel: ProcessLogLevel,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    guard case .structured(let level) = classification else {
      return XCTFail("Expected a structured Lua log line", file: file, line: line)
    }
    XCTAssertEqual(level.rawValue, expectedLevel.rawValue, file: file, line: line)
  }

  private func snapshot(
    runtime: IPC.RuntimeMetrics,
    processCPUPercent: Double? = nil,
    processResidentSizeBytes: UInt64? = nil
  ) -> IPC.MetricsSnapshot {
    IPC.MetricsSnapshot(
      timestamp: Date(timeIntervalSince1970: 0),
      collectionEnabled: false,
      sampleIntervalSeconds: 1,
      process: IPC.ProcessMetrics(
        name: "EasyBar",
        running: true,
        cpuPercent: processCPUPercent,
        residentSizeBytes: processResidentSizeBytes
      ),
      lua: IPC.ProcessMetrics(name: "lua", running: true),
      runtime: runtime,
      agents: [],
      widgets: [
        IPC.WidgetMetrics(
          id: "github_inbox_timer",
          updatesTotal: 1,
          updatesPerSecond: 0,
          lastNodeCount: 1,
          lastUpdatedAt: nil
        )
      ],
      events: [
        IPC.CounterMetrics(
          name: "network_change",
          total: 3,
          perSecond: 0,
          droppedTotal: 0,
          coalescedTotal: 0
        )
      ]
    )
  }

  private func runtimeMetrics(
    subscribedEvents: [String]? = nil,
    stderrLines: Int,
    luaLogLines: Int? = nil,
    luaWarningLines: Int? = nil,
    luaErrorLines: Int? = nil,
    luaRawStderrLines: Int? = nil,
    eventsPerSecond: Double = 0,
    treeUpdatesPerSecond: Double = 0
  ) -> IPC.RuntimeMetrics {
    IPC.RuntimeMetrics(
      subscriberCount: 0,
      luaRestartCount: 0,
      luaReady: true,
      subscribedEventCount: subscribedEvents?.count ?? 0,
      subscribedEvents: subscribedEvents,
      totalEvents: 0,
      appEvents: 0,
      widgetEvents: 0,
      eventsPerSecond: eventsPerSecond,
      droppedEvents: 0,
      droppedEventsPerSecond: 0,
      coalescedEvents: 0,
      coalescedEventsPerSecond: 0,
      transportLines: 4,
      stderrLines: stderrLines,
      luaWrites: 5,
      luaLogLines: luaLogLines,
      luaWarningLines: luaWarningLines,
      luaErrorLines: luaErrorLines,
      luaRawStderrLines: luaRawStderrLines,
      treeUpdates: 0,
      treeUpdatesPerSecond: treeUpdatesPerSecond,
      decodeErrors: 0,
      luaRuntimeInputOverflows: 0,
      luaEventQueueDepth: 0,
      luaEventQueueOverflows: 0,
      lastTreeRoot: nil,
      lastTreeNodeCount: nil,
      lastTreeAt: nil
    )
  }
}
