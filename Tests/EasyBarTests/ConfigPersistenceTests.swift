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
