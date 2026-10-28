import Darwin
import Foundation
import XCTest

@testable import EasyBarCtl

final class WidgetPackageOperationLockTests: XCTestCase {
  func testSecondDescriptorCannotAcquireExclusiveLockUntilFirstOperationFinishes() throws {
    let directory = FileManager.default.temporaryDirectory.appending(
      path: "easybar-lock-test-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: directory) }

    let lockPath = directory.appending(path: ".package-operation.lock").path
    try WidgetPackageOperationLock.withExclusiveAccess(
      to: directory,
      fileManager: .default
    ) {
      let fd = Darwin.open(lockPath, O_RDWR | O_CLOEXEC)
      XCTAssertGreaterThanOrEqual(fd, 0)
      guard fd >= 0 else { return }
      defer { _ = Darwin.close(fd) }

      XCTAssertEqual(easybarAdvisoryFlock(fd, LOCK_EX | LOCK_NB), -1)
      XCTAssertEqual(errno, EWOULDBLOCK)
    }

    let fd = Darwin.open(lockPath, O_RDWR | O_CLOEXEC)
    XCTAssertGreaterThanOrEqual(fd, 0)
    guard fd >= 0 else { return }
    defer { _ = Darwin.close(fd) }
    XCTAssertEqual(easybarAdvisoryFlock(fd, LOCK_EX | LOCK_NB), 0)
    _ = easybarAdvisoryFlock(fd, LOCK_UN)
  }

  func testRejectsSymlinkAsLockFile() throws {
    let directory = FileManager.default.temporaryDirectory.appending(
      path: "easybar-lock-symlink-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let target = directory.appending(path: "target")
    try "untouched".write(to: target, atomically: true, encoding: .utf8)
    try FileManager.default.createSymbolicLink(
      at: directory.appending(path: ".package-operation.lock"), withDestinationURL: target)

    XCTAssertThrowsError(
      try WidgetPackageOperationLock.withExclusiveAccess(to: directory, fileManager: .default) {
        XCTFail("Must never acquire a symlinked lock")
      }
    )
    XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "untouched")
  }
}
