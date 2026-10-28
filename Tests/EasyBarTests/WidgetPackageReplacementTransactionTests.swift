import Foundation
import XCTest

@testable import EasyBarCtl

/// File manager that can simulate failures at specific replacement boundaries.
private final class ReplacementFailureFileManager: FileManager, @unchecked Sendable {
  /// Whether staged replacements should fail.
  var failStagedMove = false
  /// Whether backup restoration should fail.
  var failBackupRestoration = false

  /// Injects a failure before selected moves reach the real filesystem.
  override func moveItem(at srcURL: URL, to dstURL: URL) throws {
    if (failStagedMove && srcURL.lastPathComponent == "prepared")
      || (failBackupRestoration && srcURL.lastPathComponent.contains(".backup-"))
    {
      throw NSError(domain: "ReplacementFailureFileManager", code: 1)
    }
    try super.moveItem(at: srcURL, to: dstURL)
  }
}

final class WidgetPackageReplacementTransactionTests: XCTestCase {
  func testFailedReplacementRestoresPreviousItem() throws {
    let (directory, destination, prepared) = try makeFixture()
    defer { try? FileManager.default.removeItem(at: directory) }
    let manager = ReplacementFailureFileManager()
    manager.failStagedMove = true

    let transaction = WidgetPackageReplacementTransaction(fileManager: manager)
    XCTAssertThrowsError(try transaction.replaceItem(at: destination, with: prepared))
    XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "original")
  }

  func testFailedRestorationReportsBackupLocation() throws {
    let (directory, destination, prepared) = try makeFixture()
    defer { try? FileManager.default.removeItem(at: directory) }
    let manager = ReplacementFailureFileManager()
    manager.failStagedMove = true
    manager.failBackupRestoration = true

    let transaction = WidgetPackageReplacementTransaction(fileManager: manager)
    XCTAssertThrowsError(try transaction.replaceItem(at: destination, with: prepared)) { error in
      guard case .installConflict(let reason) = error as? WidgetPackageError else {
        return XCTFail("Expected a contextual recovery failure")
      }
      XCTAssertTrue(reason.contains("previous item remains at"))
      XCTAssertTrue(reason.contains(destination.path))
    }
    let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
    XCTAssertTrue(files.contains { $0.contains(".backup-") })
  }

  func testRollbackCanRetryFailedRestoration() throws {
    let (directory, destination, prepared) = try makeFixture()
    defer { try? FileManager.default.removeItem(at: directory) }
    let manager = ReplacementFailureFileManager()
    let transaction = WidgetPackageReplacementTransaction(fileManager: manager)
    try transaction.replaceItem(at: destination, with: prepared)

    manager.failBackupRestoration = true
    XCTAssertThrowsError(try transaction.rollback())
    manager.failBackupRestoration = false
    XCTAssertNoThrow(try transaction.rollback())
    XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "original")
  }

  private func makeFixture() throws -> (URL, URL, URL) {
    let directory = FileManager.default.temporaryDirectory.appending(
      path: "easybar-replacement-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let destination = directory.appending(path: "destination")
    let prepared = directory.appending(path: "prepared")
    try "original".write(to: destination, atomically: true, encoding: .utf8)
    try "replacement".write(to: prepared, atomically: true, encoding: .utf8)
    return (directory, destination, prepared)
  }
}
