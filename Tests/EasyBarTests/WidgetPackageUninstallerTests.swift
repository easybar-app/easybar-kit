import EasyBarShared
import Foundation
import XCTest

@testable import EasyBarCtl

final class WidgetPackageUninstallerTests: XCTestCase {
  private var directory: URL!
  private var packagesDirectory: URL!
  private var uninstaller: WidgetPackageUninstaller!

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory.appending(
      path: "easybar-package-uninstall-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    packagesDirectory = directory.appending(path: "packages", directoryHint: .isDirectory)
    uninstaller = WidgetPackageUninstaller(packagesDirectory: packagesDirectory)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
    directory = nil
    packagesDirectory = nil
    uninstaller = nil
  }

  func testUninstallProtectsDependenciesAndRemovesOnlyOwnedFiles() throws {
    let shared = InstalledWidgetPackage(
      name: "shared",
      version: "1.0.0",
      kind: .library,
      entrypoint: nil,
      dependencies: [:],
      exports: ["retry": "retry.lua"],
      source: "registry"
    )
    let clock = InstalledWidgetPackage(
      name: "clock",
      version: "2.0.0",
      kind: .widget,
      entrypoint: "widget.lua",
      dependencies: ["shared": "^1.0.0"],
      exports: [:],
      source: "registry"
    )
    try WidgetPackageDatabaseStore().write(
      InstalledWidgetPackages(
        layoutVersion: WidgetPackageStore.layoutVersion,
        packages: [clock, shared]
      ),
      to: packagesDirectory
    )
    try write("return nil\n", to: "store/clock/2.0.0/widget.lua")
    try write("return {}\n", to: "store/shared/1.0.0/retry.lua")
    try link("active/clock", to: "../store/clock/2.0.0/widget.lua")
    try link(
      "active/shared/retry.lua",
      to: "../../store/shared/1.0.0/retry.lua"
    )
    try WidgetPackagePinStore().write(["clock"], to: packagesDirectory)

    XCTAssertThrowsError(try uninstaller.uninstall(name: "shared")) { error in
      XCTAssertEqual(
        error as? WidgetPackageError,
        .packageRequired(name: "shared", dependents: ["clock"])
      )
    }

    XCTAssertEqual(try uninstaller.uninstall(name: "clock"), clock)
    XCTAssertFalse(exists("active/clock"))
    XCTAssertFalse(exists("store/clock"))
    XCTAssertTrue(exists("active/shared/retry.lua"))
    XCTAssertTrue(exists("store/shared/1.0.0/retry.lua"))
    XCTAssertEqual(try database().packages.map(\.name), ["shared"])
    XCTAssertEqual(try WidgetPackagePinStore().load(from: packagesDirectory), [])

    XCTAssertEqual(try uninstaller.uninstall(name: "shared"), shared)
    XCTAssertFalse(exists("active/shared/retry.lua"))
    XCTAssertFalse(exists("store/shared"))
    XCTAssertEqual(try database().packages, [])
  }

  func testUninstallRejectsInvalidAndMissingNames() {
    XCTAssertThrowsError(try uninstaller.uninstall(name: "../clock"))
    XCTAssertThrowsError(try uninstaller.uninstall(name: "clock")) { error in
      XCTAssertEqual(error as? WidgetPackageError, .packageNotInstalled("clock"))
    }
  }

  private func write(_ contents: String, to relativePath: String) throws {
    let url = packagesDirectory.appending(path: relativePath)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try contents.write(to: url, atomically: true, encoding: .utf8)
  }

  private func link(_ relativePath: String, to destination: String) throws {
    let url = packagesDirectory.appending(path: relativePath)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try FileManager.default.createSymbolicLink(
      atPath: url.path,
      withDestinationPath: destination
    )
  }

  private func exists(_ relativePath: String) -> Bool {
    FileManager.default.fileExists(atPath: packagesDirectory.appending(path: relativePath).path)
  }

  private func database() throws -> InstalledWidgetPackages {
    try WidgetPackageDatabaseStore().load(from: packagesDirectory)
  }
}
