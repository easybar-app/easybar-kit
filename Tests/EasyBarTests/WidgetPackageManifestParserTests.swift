import Foundation
import XCTest

@testable import EasyBarCtl

final class WidgetPackageManifestParserTests: XCTestCase {
  func testParsesManifestVersionTwo() throws {
    let directory = try makePackage(
      manifest: """
        manifest_version = 2
        name = "clock"
        version = "1.2.3"
        minimum_easybar_kit_version = "0.50.0"
        kind = "widget"
        entrypoint = "widget.lua"
        """
    )
    defer { try? FileManager.default.removeItem(at: directory) }

    let manifest = try WidgetPackageManifestParser.parse(directory: directory)

    XCTAssertEqual(manifest.name, "clock")
    XCTAssertEqual(manifest.version, SemanticVersion("1.2.3"))
    XCTAssertEqual(manifest.minimumEasyBarKitVersion, SemanticVersion("0.50.0"))
  }

  func testRejectsPreviousManifestVersion() throws {
    let directory = try makePackage(
      manifest: """
        manifest_version = 1
        name = "clock"
        version = "1.2.3"
        minimum_easybar_kit_version = "0.50.0"
        kind = "widget"
        entrypoint = "widget.lua"
        """
    )
    defer { try? FileManager.default.removeItem(at: directory) }

    XCTAssertThrowsError(try WidgetPackageManifestParser.parse(directory: directory)) { error in
      XCTAssertEqual(
        error as? WidgetPackageError,
        .invalidManifest("manifest_version must be 2")
      )
    }
  }

  func testRejectsUnsupportedManifestFields() throws {
    let directory = try makePackage(
      manifest: """
        manifest_version = 2
        name = "clock"
        version = "1.2.3"
        minimum_easybar_kit_version = "0.50.0"
        kind = "widget"
        entrypoint = "widget.lua"
        minimum_easybar_version = "0.40.0"
        """
    )
    defer { try? FileManager.default.removeItem(at: directory) }

    XCTAssertThrowsError(try WidgetPackageManifestParser.parse(directory: directory)) { error in
      XCTAssertEqual(
        error as? WidgetPackageError,
        .invalidManifest("unsupported manifest fields: minimum_easybar_version")
      )
    }
  }

  func testRejectsSymbolicLinkUsedAsEntrypoint() throws {
    let directory = try makePackage(
      manifest: """
        manifest_version = 2
        name = "clock"
        version = "1.2.3"
        minimum_easybar_kit_version = "0.50.0"
        kind = "widget"
        entrypoint = "widget.lua"
        """
    )
    defer { try? FileManager.default.removeItem(at: directory) }

    let entrypoint = directory.appending(path: "widget.lua")
    let target = directory.appending(path: "target.lua")
    try FileManager.default.removeItem(at: entrypoint)
    try "return nil\n".write(to: target, atomically: true, encoding: .utf8)
    try FileManager.default.createSymbolicLink(
      at: entrypoint,
      withDestinationURL: target
    )

    XCTAssertThrowsError(try WidgetPackageManifestParser.parse(directory: directory)) { error in
      XCTAssertEqual(
        error as? WidgetPackageError,
        .invalidManifest("unsafe or missing entrypoint: widget.lua")
      )
    }
  }

  func testRejectsDirectoryUsedAsEntrypoint() throws {
    let directory = try makePackage(
      manifest: """
        manifest_version = 2
        name = "clock"
        version = "1.2.3"
        minimum_easybar_kit_version = "0.50.0"
        kind = "widget"
        entrypoint = "widget.lua"
        """
    )
    defer { try? FileManager.default.removeItem(at: directory) }

    let entrypoint = directory.appending(path: "widget.lua")
    try FileManager.default.removeItem(at: entrypoint)
    try FileManager.default.createDirectory(at: entrypoint, withIntermediateDirectories: false)

    XCTAssertThrowsError(try WidgetPackageManifestParser.parse(directory: directory)) { error in
      XCTAssertEqual(
        error as? WidgetPackageError,
        .invalidManifest("unsafe or missing entrypoint: widget.lua")
      )
    }
  }

  private func makePackage(manifest: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appending(
      path: "easybar-manifest-parser-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try manifest.write(
      to: directory.appending(path: "package.toml"),
      atomically: true,
      encoding: .utf8
    )
    try "return nil\n".write(
      to: directory.appending(path: "widget.lua"),
      atomically: true,
      encoding: .utf8
    )
    return directory
  }
}
