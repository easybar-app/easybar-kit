import EasyBarShared
import Foundation
import XCTest

@testable import EasyBarCtl

final class WidgetPackageUninstallerTests: XCTestCase {
  private var directory: URL!
  private var packagesDirectory: URL!
  private var widgetsDirectory: URL!
  private var uninstaller: WidgetPackageUninstaller!

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory.appending(
      path: "easybar-package-uninstall-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    packagesDirectory = directory.appending(path: "packages", directoryHint: .isDirectory)
    widgetsDirectory = directory.appending(path: "widgets", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: widgetsDirectory, withIntermediateDirectories: true)
    uninstaller = WidgetPackageUninstaller(
      packagesDirectory: packagesDirectory,
      legacyWidgetsDirectory: widgetsDirectory
    )
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
    directory = nil
    packagesDirectory = nil
    widgetsDirectory = nil
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
    try write("return nil\n", to: "active/clock/widget.lua")
    try write("return {}\n", to: "active/shared/retry.lua")
    try write("return nil\n", to: "store/clock/2.0.0/widget.lua")
    try write("return {}\n", to: "store/shared/1.0.0/retry.lua")
    try "return 'manual'\n".write(
      to: widgetsDirectory.appending(path: "manual.lua"),
      atomically: true,
      encoding: .utf8
    )

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

    XCTAssertEqual(try uninstaller.uninstall(name: "shared"), shared)
    XCTAssertFalse(exists("active/shared/retry.lua"))
    XCTAssertFalse(exists("store/shared"))
    XCTAssertTrue(FileManager.default.fileExists(atPath: widgetsDirectory.appending(path: "manual.lua").path))
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

  private func exists(_ relativePath: String) -> Bool {
    FileManager.default.fileExists(atPath: packagesDirectory.appending(path: relativePath).path)
  }

  private func database() throws -> InstalledWidgetPackages {
    try WidgetPackageDatabaseStore().load(from: packagesDirectory)
  }
}
