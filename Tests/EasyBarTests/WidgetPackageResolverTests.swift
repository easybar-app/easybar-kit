import EasyBarShared
import Foundation
import XCTest

@testable import EasyBarCtl

final class WidgetPackageResolverTests: XCTestCase {
  func testRejectsPackageRequiringNewerKit() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(
      path: "easybar-resolver-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    let package = directory.appending(path: "clock", directoryHint: .isDirectory)
    let downloads = directory.appending(path: "downloads", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    try """
    manifest_version = 2
    name = "clock"
    version = "1.0.0"
    minimum_easybar_kit_version = "0.51.0"
    kind = "widget"
    entrypoint = "widget.lua"
    """.write(
      to: package.appending(path: "package.toml"),
      atomically: true,
      encoding: .utf8
    )
    try "return nil\n".write(
      to: package.appending(path: "widget.lua"),
      atomically: true,
      encoding: .utf8
    )

    let resolver = WidgetPackageResolver(
      registrySource: nil,
      useRegistry: false,
      temporaryDirectory: downloads,
      installed: [],
      logger: ProcessLogger(label: "resolver-tests", minimumLevel: .error),
      currentKitVersion: SemanticVersion("0.50.0")
    )

    do {
      _ = try await resolver.resolve(source: package.path, sha256: nil)
      XCTFail("Expected EasyBarKit version compatibility failure")
    } catch let error as WidgetPackageError {
      XCTAssertEqual(
        error,
        .incompatibleKitVersion(package: "clock", minimum: "0.51.0", current: "0.50.0")
      )
    }
  }
  func testRejectsInvalidExactRegistryVersion() async throws {
    let downloads = FileManager.default.temporaryDirectory.appending(
      path: "easybar-resolver-downloads-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: downloads) }

    let resolver = WidgetPackageResolver(
      registrySource: nil,
      useRegistry: true,
      temporaryDirectory: downloads,
      installed: [],
      logger: ProcessLogger(label: "resolver-tests", minimumLevel: .error),
      currentKitVersion: nil
    )

    do {
      _ = try await resolver.resolve(source: "clock@latest", sha256: nil)
      XCTFail("Expected an invalid registry package version")
    } catch let error as WidgetPackageError {
      XCTAssertEqual(error, .invalidSource("invalid package version 'latest'"))
    }
  }

  func testHTTPSArchiveRequiresChecksumBeforeDownloading() async throws {
    let downloads = FileManager.default.temporaryDirectory.appending(
      path: "easybar-resolver-downloads-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: downloads) }

    let resolver = WidgetPackageResolver(
      registrySource: nil,
      useRegistry: false,
      temporaryDirectory: downloads,
      installed: [],
      logger: ProcessLogger(label: "resolver-tests", minimumLevel: .error),
      currentKitVersion: nil
    )
    let source = "https://example.invalid/package.tar.gz"

    do {
      _ = try await resolver.resolve(source: source, sha256: nil)
      XCTFail("Expected checksum requirement before network access")
    } catch let error as WidgetPackageError {
      XCTAssertEqual(error, .checksumRequired(source))
    }
  }

  func testRejectsPlaintextHTTPArchiveSources() async throws {
    let downloads = FileManager.default.temporaryDirectory.appending(
      path: "easybar-resolver-downloads-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: downloads) }

    let resolver = WidgetPackageResolver(
      registrySource: nil,
      useRegistry: false,
      temporaryDirectory: downloads,
      installed: [],
      logger: ProcessLogger(label: "resolver-tests", minimumLevel: .error),
      currentKitVersion: nil
    )

    do {
      _ = try await resolver.resolve(source: "http://example.invalid/package.tar.gz", sha256: nil)
      XCTFail("Expected plaintext HTTP to be rejected")
    } catch let error as WidgetPackageError {
      XCTAssertEqual(error, .invalidSource("unsupported URL scheme 'http'"))
    }
  }

  func testPinnedInstalledDependencyCannotBeReplacedDuringResolution() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(
      path: "easybar-resolver-pinned-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    let package = directory.appending(path: "consumer", directoryHint: .isDirectory)
    let downloads = directory.appending(path: "downloads", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    try """
    manifest_version = 2
    name = "consumer"
    version = "1.0.0"
    minimum_easybar_kit_version = "0.1.0"
    kind = "widget"
    entrypoint = "widget.lua"

    [dependencies]
    shared = "^2.0.0"
    """.write(
      to: package.appending(path: "package.toml"),
      atomically: true,
      encoding: .utf8
    )
    try "return nil\n".write(
      to: package.appending(path: "widget.lua"),
      atomically: true,
      encoding: .utf8
    )

    let installed = InstalledWidgetPackage(
      name: "shared",
      version: "1.0.0",
      kind: .library,
      entrypoint: nil,
      dependencies: [:],
      exports: ["shared": "shared.lua"],
      source: "https://example.com/shared-1.0.0.tar.gz"
    )
    let resolver = WidgetPackageResolver(
      registrySource: nil,
      useRegistry: false,
      temporaryDirectory: downloads,
      installed: [installed],
      protectedPackages: ["shared"],
      logger: ProcessLogger(label: "resolver-tests", minimumLevel: .error),
      currentKitVersion: SemanticVersion("1.0.0")
    )

    do {
      _ = try await resolver.resolve(source: package.path, sha256: nil)
      XCTFail("Expected the pinned dependency to block replacement")
    } catch let error as WidgetPackageError {
      XCTAssertEqual(error, .packagePinned("shared"))
    }
  }

}
