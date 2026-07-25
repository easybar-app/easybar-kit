import EasyBarShared
import Foundation
import XCTest

final class ProcessLoggerLiveSinkTests: XCTestCase {
  func testLiveSinkReceivesTraceWithoutChangingPersistentLevel() throws {
    let directoryURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("easybar-live-sink-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directoryURL) }

    let fileURL = directoryURL.appendingPathComponent("easybar.out")
    let logger = ProcessLogger(
      label: "easybar",
      minimumLevel: .info,
      outputStream: nil,
      errorStream: nil
    )
    logger.configureFileLogging(enabled: true, path: fileURL.path)

    let events = LockedState<[ProcessLogEvent]>([])
    logger.configureLiveSink(
      minimumLevel: { _ in .trace },
      emit: { event, _ in
        events.withLock { $0.append(event) }
      }
    )

    logger.trace(
      "trace only for subscriber",
      .field("widget", "brew-inbox"),
      .field("runtime", ProcessLogRuntime.lua.rawValue)
    )
    logger.info("persistent info")
    logger.configureFileLogging(enabled: false, path: "")

    let fileContents = try String(contentsOf: fileURL, encoding: .utf8)
    XCTAssertFalse(fileContents.contains("trace only for subscriber"))
    XCTAssertTrue(fileContents.contains("persistent info"))
    XCTAssertEqual(logger.minimumLevel, .info)

    let snapshot = events.withLock { $0 }
    XCTAssertEqual(snapshot.map(\.message), ["trace only for subscriber", "persistent info"])
    XCTAssertEqual(snapshot.first?.level, .trace)
    XCTAssertEqual(snapshot.first?.runtime, .lua)
    XCTAssertEqual(snapshot.first?.widget, "brew-inbox")
    XCTAssertEqual(snapshot.first?.fields["subsystem"], "easybar")
  }

  func testLiveSinkNormalizesAgentSourceNames() {
    let logger = ProcessLogger(
      label: "easybar-calendar-agent",
      minimumLevel: .info,
      outputStream: nil,
      errorStream: nil
    )
    let events = LockedState<[ProcessLogEvent]>([])
    logger.configureLiveSink(
      minimumLevel: { _ in .trace },
      emit: { event, _ in
        events.withLock { $0.append(event) }
      }
    )

    logger.trace("calendar trace")

    XCTAssertEqual(events.withLock { $0.first?.source }, "calendar-agent")
    XCTAssertEqual(events.withLock { $0.first?.runtime }, .agent)
  }

  func testLiveSinkDoesNotReceiveRecordsBelowItsOwnLevel() {
    let logger = ProcessLogger(
      label: "easybar",
      minimumLevel: .error,
      outputStream: nil,
      errorStream: nil
    )
    let events = LockedState<[ProcessLogEvent]>([])
    logger.configureLiveSink(
      minimumLevel: { _ in .debug },
      emit: { event, _ in
        events.withLock { $0.append(event) }
      }
    )

    logger.trace("hidden trace")
    logger.debug("visible debug")

    XCTAssertEqual(events.withLock { $0.map(\.message) }, ["visible debug"])
    XCTAssertEqual(logger.minimumLevel, .error)
  }
}
