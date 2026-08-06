import EasyBarShared
import Foundation
import SwiftTOMLEdit
import XCTest

@testable import EasyBarApp

final class ConfigPersistenceHardeningTests: XCTestCase {
  @MainActor
  func testAtomicEditPreservesExistingFilePermissions() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let configURL = directory.appendingPathComponent("config.toml")
    try "[app]\ndevelop = false\n".write(
      to: configURL,
      atomically: false,
      encoding: .utf8
    )
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: configURL.path
    )

    let persistence = ConfigPersistence(configPath: configURL.path, logger: makeLogger())
    XCTAssertTrue(
      persistence.apply([
        TOMLEdit(path: ["app", "develop"], value: .bool(true))
      ])
    )

    XCTAssertEqual(try permissions(at: configURL), 0o600)
    XCTAssertTrue(try String(contentsOf: configURL, encoding: .utf8).contains("develop = true"))
  }

  @MainActor
  func testNewConfigUsesOwnerOnlyFilePermissions() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let configURL =
      directory
      .appendingPathComponent("nested", isDirectory: true)
      .appendingPathComponent("config.toml")
    let persistence = ConfigPersistence(configPath: configURL.path, logger: makeLogger())

    XCTAssertTrue(
      persistence.apply([
        TOMLEdit(path: ["app", "develop"], value: .bool(true))
      ])
    )

    XCTAssertEqual(try permissions(at: configURL), 0o600)
    XCTAssertTrue(try String(contentsOf: configURL, encoding: .utf8).contains("develop = true"))
  }

  @MainActor
  func testAtomicEditPreservesSymbolicLinkAndUpdatesItsTarget() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let targetURL = directory.appendingPathComponent("managed-config.toml")
    try "[app]\ndevelop = false\n".write(
      to: targetURL,
      atomically: false,
      encoding: .utf8
    )
    let configURL = directory.appendingPathComponent("config.toml")
    try FileManager.default.createSymbolicLink(at: configURL, withDestinationURL: targetURL)

    let persistence = ConfigPersistence(configPath: configURL.path, logger: makeLogger())
    XCTAssertTrue(
      persistence.apply([
        TOMLEdit(path: ["app", "develop"], value: .bool(true))
      ])
    )

    XCTAssertNoThrow(try FileManager.default.destinationOfSymbolicLink(atPath: configURL.path))
    XCTAssertTrue(try String(contentsOf: targetURL, encoding: .utf8).contains("develop = true"))
  }

  @MainActor
  func testLoggingLevelOverrideUpdatesSnapshotAndLiveConfig() {
    let config = Config.makeUnloadedConfig()
    let store = ConfigSnapshotStore(
      snapshot: config.snapshot(),
      snapshotDidChange: { config.apply($0) }
    )

    store.applyLoggingLevelOverride(.debug)

    XCTAssertEqual(store.snapshot.logging.level, .debug)
    XCTAssertEqual(config.loggingLevel, .debug)
  }

  @MainActor
  func testLoggingLevelEditPreservesCommentsAndUnrelatedSettings() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let configURL = directory.appendingPathComponent("config.toml")
    try """
    # Keep this comment.
    [app]
    develop = true

    [logging]
    enabled = true
    level = "info" # Keep this inline comment.
    directory = "~/.local/state/easybar"
    """.write(to: configURL, atomically: false, encoding: .utf8)

    let persistence = ConfigPersistence(configPath: configURL.path, logger: makeLogger())
    XCTAssertTrue(
      persistence.apply([
        TOMLEdit(path: ["logging", "level"], value: .string("debug"))
      ])
    )

    let contents = try String(contentsOf: configURL, encoding: .utf8)
    let table = try TOMLTable(string: contents)
    XCTAssertEqual(table["logging"]?.table?["level"]?.string, "debug")
    XCTAssertEqual(table["logging"]?.table?["enabled"]?.bool, true)
    XCTAssertEqual(table["app"]?.table?["develop"]?.bool, true)
    XCTAssertTrue(contents.contains("# Keep this comment."))
    XCTAssertTrue(contents.contains("# Keep this inline comment."))
  }

  @MainActor
  func testWidgetSettingIsPersistedBelowReservedWidgetsNamespace() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let configURL = directory.appendingPathComponent("config.toml")
    try "[app]\ndevelop = false\n".write(to: configURL, atomically: false, encoding: .utf8)

    let persistence = ConfigPersistence(configPath: configURL.path, logger: makeLogger())
    XCTAssertTrue(
      persistence.apply([
        TOMLEdit(
          path: ["widgets", "github-inbox", "merge_method"],
          value: .string("rebase")
        )
      ])
    )

    let table = try TOMLTable(string: String(contentsOf: configURL, encoding: .utf8))
    XCTAssertEqual(
      table["widgets"]?.table?["github-inbox"]?.table?["merge_method"]?.string,
      "rebase"
    )
    XCTAssertEqual(table["app"]?.table?["develop"]?.bool, false)
  }

  private func makeTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("easybar-config-persistence-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  private func permissions(at url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
  }

  private func makeLogger() -> ProcessLogger {
    ProcessLogger(
      label: "config-persistence-tests",
      minimumLevel: .error,
      outputStream: nil,
      errorStream: nil
    )
  }
}
