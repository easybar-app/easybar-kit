import Foundation
import XCTest

@testable import EasyBarShared

final class ProcessLogRecordTests: XCTestCase {
  func testParserDecodesStructuredFieldsAndRuntimeMetadata() throws {
    let record = ProcessLogRecord.parse(
      "[2026-07-21T23:11:10.117+02:00] [DEBUG] lua command started "
        + "request_id=lua-19 widget=tailscale detail=\"hello world\" "
        + "run_id=run-1 subsystem=easybar.app.runtime.widget_engine.commands",
      source: "easybar"
    )

    XCTAssertNotNil(record.timestamp)
    XCTAssertEqual(record.level, .debug)
    XCTAssertEqual(record.message, "lua command started")
    XCTAssertEqual(record.fields["request_id"], "lua-19")
    XCTAssertEqual(record.fields["detail"], "hello world")
    XCTAssertEqual(record.fields["run_id"], "run-1")
    XCTAssertEqual(record.widget, "tailscale")
    XCTAssertEqual(record.runtime, .lua)
  }

  func testParserInfersLegacyLuaWidgetWithoutSubsystemMetadata() {
    let record = ProcessLogRecord.parse(
      "[2026-07-21T23:11:10.117+02:00] [INFO ] refresh completed widget=brew-inbox",
      source: "easybar"
    )

    XCTAssertEqual(record.widget, "brew-inbox")
    XCTAssertEqual(record.runtime, .lua)
    XCTAssertTrue(ProcessLogFilter(widget: "brew-inbox", runtime: .lua).matches(record))
  }

  func testParserInfersLegacyLuaRuntimeComponentWithoutSubsystemMetadata() {
    let record = ProcessLogRecord.parse(
      "[2026-07-21T23:11:10.117+02:00] [INFO ] runtime ready component=runtime",
      source: "easybar"
    )

    XCTAssertEqual(record.runtime, .lua)
  }

  func testLiveAgentLoggerLabelsInferAgentRuntime() {
    let calendar = ProcessLogRecord.parse(
      "[2026-07-21T23:11:10.117+02:00] [TRACE] calendar trace",
      source: "easybar-calendar-agent"
    )
    let network = ProcessLogRecord.parse(
      "[2026-07-21T23:11:10.117+02:00] [TRACE] network trace",
      source: "easybar-network-agent"
    )

    XCTAssertEqual(calendar.runtime, .agent)
    XCTAssertEqual(network.runtime, .agent)
  }

  func testParserInfersNativeWidgetFromSubsystem() {
    let record = ProcessLogRecord.parse(
      "[2026-07-21T23:11:10.117+02:00] [WARN ] action failed "
        + "subsystem=easybar.app.services.widgets.volume",
      source: "easybar"
    )

    XCTAssertEqual(record.widget, "volume")
    XCTAssertEqual(record.runtime, .native)
  }

  func testFilterAppliesWidgetRuntimeLevelRequestAndSince() throws {
    let record = ProcessLogRecord.parse(
      "[2026-07-21T23:11:10.117+02:00] [ERROR] lua command failed "
        + "request_id=lua-19 widget=builtin_tailscale",
      source: "easybar"
    )
    let cutoff = try XCTUnwrap(ProcessLogSinceParser.parse("2026-07-21T23:00:00+02:00"))

    XCTAssertTrue(
      ProcessLogFilter(
        widget: "tailscale",
        runtime: .lua,
        minimumLevel: .debug,
        requestID: "lua-19",
        since: cutoff
      ).matches(record)
    )
    XCTAssertFalse(ProcessLogFilter(minimumLevel: .trace, requestID: "lua-20").matches(record))
  }

  func testSinceParserAcceptsRelativeDurationsAndISO8601() throws {
    let now = Date(timeIntervalSince1970: 10_000)

    XCTAssertEqual(ProcessLogSinceParser.parse("30m", now: now), now.addingTimeInterval(-1_800))
    XCTAssertEqual(ProcessLogSinceParser.parse("2h", now: now), now.addingTimeInterval(-7_200))
    XCTAssertNotNil(ProcessLogSinceParser.parse("2026-07-21T23:00:00+02:00", now: now))
    XCTAssertNil(ProcessLogSinceParser.parse("yesterday", now: now))
  }

  func testHistoryMergesProcessesAndRotationsChronologically() throws {
    let directory = try makeProcessLogDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    try write(
      "[2026-07-21T20:00:00.000+02:00] [DEBUG] oldest widget=tailscale\n",
      to: directory.appendingPathComponent("easybar.out.1")
    )
    try write(
      "[2026-07-21T20:02:00.000+02:00] [DEBUG] newest widget=tailscale\n",
      to: directory.appendingPathComponent("easybar.out")
    )
    try write(
      "[2026-07-21T20:01:00.000+02:00] [INFO ] middle\n",
      to: directory.appendingPathComponent("network-agent.out")
    )

    let all = try ProcessLogStore.history(
      in: directory.path,
      filter: ProcessLogFilter(),
      limit: nil
    )
    XCTAssertEqual(all.map(\.message), ["oldest", "middle", "newest"])

    let latestWidget = try ProcessLogStore.history(
      in: directory.path,
      filter: ProcessLogFilter(widget: "tailscale"),
      limit: 1
    )
    XCTAssertEqual(latestWidget.map(\.message), ["newest"])
  }

  func testBoundedHistoryStopsAfterNewestMatchingLine() throws {
    let directory = try makeProcessLogDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let active = directory.appendingPathComponent("easybar.out")

    var contents = Data([0xFF, 0x0A])
    contents.append(Data(repeating: 0x78, count: 128 * 1024))
    contents.append(0x0A)
    contents.append(
      Data("[2026-07-21T20:02:00.000+02:00] [INFO ] newest widget=tailscale\n".utf8)
    )
    try contents.write(to: active)

    let records = try ProcessLogStore.history(
      in: directory.path,
      filter: ProcessLogFilter(widget: "tailscale"),
      limit: 1
    )

    XCTAssertEqual(records.map(\.message), ["newest"])
  }

  func testFollowerPreservesUTF8ScalarSplitAcrossPolls() throws {
    let directory = try makeProcessLogDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let active = directory.appendingPathComponent("easybar.out")
    try write(
      "[2026-07-21T20:00:00.000+02:00] [INFO ] existing\n",
      to: active
    )

    let follower = ProcessLogFollower(directory: directory.path, filter: ProcessLogFilter())
    let scalar = Data("🔒".utf8)
    var firstChunk = Data("[2026-07-21T20:01:00.000+02:00] [INFO ] split ".utf8)
    firstChunk.append(contentsOf: scalar.prefix(2))
    try append(firstChunk, to: active)
    XCTAssertTrue(follower.poll().isEmpty)

    var secondChunk = Data(scalar.dropFirst(2))
    secondChunk.append(0x0A)
    try append(secondChunk, to: active)
    XCTAssertEqual(follower.poll().map(\.message), ["split 🔒"])
  }

  func testFollowerReadsAppendsAndContinuesAcrossRotation() throws {
    let directory = try makeProcessLogDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let active = directory.appendingPathComponent("easybar.out")
    let archive = directory.appendingPathComponent("easybar.out.1")
    try write(
      "[2026-07-21T20:00:00.000+02:00] [INFO ] existing\n",
      to: active
    )

    let follower = ProcessLogFollower(directory: directory.path, filter: ProcessLogFilter())
    try append(
      "[2026-07-21T20:01:00.000+02:00] [INFO ] appended\n",
      to: active
    )
    XCTAssertEqual(follower.poll().map(\.message), ["appended"])

    try FileManager.default.moveItem(at: active, to: archive)
    try write(
      "[2026-07-21T20:02:00.000+02:00] [INFO ] after rotation\n",
      to: active
    )
    XCTAssertEqual(follower.poll().map(\.message), ["after rotation"])
  }
}

private func makeProcessLogDirectory() throws -> URL {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("easybar-process-log-tests-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory
}

private func write(_ text: String, to url: URL) throws {
  try text.write(to: url, atomically: true, encoding: .utf8)
}

private func append(_ text: String, to url: URL) throws {
  try append(Data(text.utf8), to: url)
}

private func append(_ data: Data, to url: URL) throws {
  let handle = try FileHandle(forWritingTo: url)
  defer { try? handle.close() }
  try handle.seekToEnd()
  try handle.write(contentsOf: data)
}
