import EasyBarShared
import Foundation
import XCTest

@testable import EasyBarCtl

final class WidgetPackagePinManagerTests: XCTestCase {
  private var directory: URL!
  private var manager: WidgetPackagePinManager!

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory.appending(
      path: "easybar-package-pin-tests-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try WidgetPackageDatabaseStore().write(
      InstalledWidgetPackages(
        layoutVersion: WidgetPackageStore.layoutVersion,
        packages: [package(name: "brew", version: "0.4.4")]
      ),
      to: directory
    )
    manager = WidgetPackagePinManager(packagesDirectory: directory)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
    directory = nil
    manager = nil
  }

  func testPinAndUnpinPersistPolicy() throws {
    let pinned = try manager.pin(name: "brew")
    XCTAssertEqual(pinned.name, "brew")
    XCTAssertEqual(try WidgetPackagePinStore().load(from: directory), ["brew"])

    let unpinned = try manager.unpin(name: "brew")
    XCTAssertEqual(unpinned.name, "brew")
    XCTAssertEqual(try WidgetPackagePinStore().load(from: directory), [])
  }

  func testPinAndUnpinRejectInvalidState() throws {
    do {
      _ = try manager.pin(name: "missing")
      XCTFail("Expected pinning a missing package to fail")
    } catch let error as WidgetPackageError {
      XCTAssertEqual(error, .packageNotInstalled("missing"))
    }

    _ = try manager.pin(name: "brew")
    do {
      _ = try manager.pin(name: "brew")
      XCTFail("Expected pinning an already pinned package to fail")
    } catch let error as WidgetPackageError {
      XCTAssertEqual(error, .packageAlreadyPinned("brew"))
    }

    _ = try manager.unpin(name: "brew")
    do {
      _ = try manager.unpin(name: "brew")
      XCTFail("Expected unpinning an unpinned package to fail")
    } catch let error as WidgetPackageError {
      XCTAssertEqual(error, .packageNotPinned("brew"))
    }
  }

  func testPinStoreRejectsInvalidState() throws {
    try """
    {
      "layout_version": 1,
      "packages": ["brew", "brew"]
    }
    """.write(
      to: directory.appending(path: "pins.json"),
      atomically: true,
      encoding: .utf8
    )

    do {
      _ = try WidgetPackagePinStore().load(from: directory)
      XCTFail("Expected duplicate package pins to fail")
    } catch let error as WidgetPackageError {
      XCTAssertEqual(error, .installConflict("package pins contain duplicate names"))
    }
  }

  private func package(name: String, version: String) -> InstalledWidgetPackage {
    InstalledWidgetPackage(
      name: name,
      version: version,
      kind: .widget,
      entrypoint: "widget.lua",
      dependencies: [:],
      exports: [:],
      source: "https://example.com/\(name)-\(version).tar.gz"
    )
  }
}
