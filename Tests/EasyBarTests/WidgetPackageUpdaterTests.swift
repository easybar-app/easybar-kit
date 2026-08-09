import CryptoKit
import EasyBarShared
import Foundation
import XCTest

@testable import EasyBarCtl

final class WidgetPackageUpdaterTests: XCTestCase {
  private var directory: URL!
  private var packagesDirectory: URL!
  private var legacyWidgetsDirectory: URL!
  private var installer: WidgetPackageInstaller!
  private var updater: WidgetPackageUpdater!

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory.appending(
      path: "easybar-package-update-tests-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    packagesDirectory = directory.appending(path: "packages", directoryHint: .isDirectory)
    legacyWidgetsDirectory = directory.appending(path: "widgets", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let logger = ProcessLogger(label: "package-update-tests", minimumLevel: .error)
    installer = WidgetPackageInstaller(
      logger: logger,
      packagesDirectory: packagesDirectory,
      legacyWidgetsDirectory: legacyWidgetsDirectory
    )
    updater = WidgetPackageUpdater(
      logger: logger,
      packagesDirectory: packagesDirectory,
      legacyWidgetsDirectory: legacyWidgetsDirectory
    )
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
    directory = nil
    packagesDirectory = nil
    legacyWidgetsDirectory = nil
    installer = nil
    updater = nil
  }

  func testOutdatedAndUpdateAllOnlyUseRegistryManagedPackages() async throws {
    let oldArchive = try packageArchive(name: "clock", version: "1.0.0")
    let newArchive = try packageArchive(name: "clock", version: "1.1.0")
    _ = try await install(source: oldArchive.path, useRegistry: false)

    let localPackage = try packageDirectory(name: "personal", version: "1.0.0")
    _ = try await install(source: localPackage.path, useRegistry: false)
    let registry = try registryIndex(entries: [
      registryEntry(name: "clock", latest: "1.1.0", archives: [oldArchive, newArchive]),
      registryEntry(
        name: "personal", latest: "2.0.0",
        archives: [
          try packageArchive(name: "personal", version: "2.0.0")
        ]),
    ])

    let outdated = try await updater.outdated(registrySource: registry.path)
    XCTAssertEqual(
      outdated,
      [
        OutdatedWidgetPackage(
          name: "clock",
          installedVersion: "1.0.0",
          availableVersion: "1.1.0",
          kind: .widget
        )
      ]
    )

    let changes = try await updater.update(
      options: WidgetPackageUpdateOptions(selection: .all, registry: registry.path)
    )
    XCTAssertEqual(changes.map(\.package.name), ["clock"])
    XCTAssertEqual(changes.first?.previousVersion, "1.0.0")
    XCTAssertEqual(changes.first?.package.version, "1.1.0")
    XCTAssertTrue(fileExists("store/clock/1.0.0"))
    XCTAssertTrue(fileExists("store/clock/1.1.0"))
    XCTAssertEqual(try symbolicLinkDestination("active/clock"), "../store/clock/1.1.0")
    XCTAssertEqual(try installedPackage(named: "personal")?.version, "1.0.0")
  }

  func testNamedUpdateRejectsALocalPackageWithARegistryName() async throws {
    let localPackage = try packageDirectory(name: "personal", version: "1.0.0")
    _ = try await install(source: localPackage.path, useRegistry: false)
    let registryArchive = try packageArchive(name: "personal", version: "2.0.0")
    let registry = try registryIndex(entries: [
      registryEntry(name: "personal", latest: "2.0.0", archives: [registryArchive])
    ])

    do {
      _ = try await updater.update(
        options: WidgetPackageUpdateOptions(
          selection: .package("personal"),
          registry: registry.path
        )
      )
      XCTFail("Expected a local package update to be rejected")
    } catch let error as WidgetPackageError {
      XCTAssertEqual(error, .packageNotManagedByRegistry("personal"))
    }
  }

  private func install(source: String, useRegistry: Bool) async throws
    -> [InstalledWidgetPackage]
  {
    try await installer.install(
      options: WidgetPackageInstallOptions(
        source: source,
        sha256: nil,
        registry: nil,
        useRegistry: useRegistry,
        force: false
      )
    )
  }

  private func packageDirectory(name: String, version: String) throws -> URL {
    let package = directory.appending(
      path: "\(name)-\(version)-source",
      directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
    try """
    manifest_version = 1
    name = "\(name)"
    version = "\(version)"
    kind = "widget"
    entrypoint = "widget.lua"
    """.write(to: package.appending(path: "package.toml"), atomically: true, encoding: .utf8)
    try "return nil\n".write(
      to: package.appending(path: "widget.lua"),
      atomically: true,
      encoding: .utf8
    )
    return package
  }

  private func packageArchive(name: String, version: String) throws -> URL {
    let package = try packageDirectory(name: name, version: version)
    let archive = directory.appending(path: "\(name)-\(version).tar.gz")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
    process.arguments = [
      "-czf", archive.path, "-C", package.path, "package.toml", "widget.lua",
    ]
    try process.run()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    return archive
  }

  private func registryEntry(
    name: String,
    latest: String,
    archives: [URL]
  ) throws -> String {
    let versions = try archives.map { archive -> String in
      let version = archive.deletingPathExtension().deletingPathExtension().lastPathComponent
        .replacingOccurrences(of: "\(name)-", with: "")
      let digest = SHA256.hash(data: try Data(contentsOf: archive)).map {
        String(format: "%02x", $0)
      }.joined()
      return """
        {
          "version": "\(version)",
          "archive": "\(archive.absoluteString)",
          "sha256": "\(digest)"
        }
        """
    }
    return """
      {
        "name": "\(name)",
        "kind": "widget",
        "latest": "\(latest)",
        "description": "\(name)",
        "categories": ["test"],
        "versions": [\(versions.joined(separator: ","))]
      }
      """
  }

  private func registryIndex(entries: [String]) throws -> URL {
    let index = directory.appending(path: "index.json")
    try """
    {"registry_version": 1, "packages": [\(entries.joined(separator: ","))]}
    """.write(to: index, atomically: true, encoding: .utf8)
    return index
  }

  private func fileExists(_ relativePath: String) -> Bool {
    FileManager.default.fileExists(atPath: packagesDirectory.appending(path: relativePath).path)
  }

  private func symbolicLinkDestination(_ relativePath: String) throws -> String {
    try FileManager.default.destinationOfSymbolicLink(
      atPath: packagesDirectory.appending(path: relativePath).path
    )
  }

  private func installedPackage(named name: String) throws -> InstalledWidgetPackage? {
    try WidgetPackageDatabaseStore().load(from: packagesDirectory).packages.first {
      $0.name == name
    }
  }
}
