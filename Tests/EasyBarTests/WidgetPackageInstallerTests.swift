import CryptoKit
import EasyBarShared
import Foundation
import XCTest

@testable import EasyBarCtl

final class WidgetPackageInstallerTests: XCTestCase {
  private var directory: URL!
  private var packagesDirectory: URL!
  private var legacyWidgetsDirectory: URL!
  private var installer: WidgetPackageInstaller!

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory.appending(
      path: "easybar-package-tests-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    packagesDirectory = directory.appending(path: "data/packages", directoryHint: .isDirectory)
    legacyWidgetsDirectory = directory.appending(path: "widgets", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    installer = WidgetPackageInstaller(
      logger: ProcessLogger(label: "package-tests", minimumLevel: .error),
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
  }

  func testInstallsSelfCreatedPackagesWithoutARegistry() async throws {
    let library = directory.appending(path: "retry-kit", directoryHint: .isDirectory)
    try writePackage(
      at: library,
      manifest: """
        manifest_version = 1
        name = "retry-kit"
        version = "1.2.0"
        kind = "library"

        [exports]
        retry = "retry.lua"
        "retry.policy" = "policy.lua"
        """,
      files: [
        "retry.lua": "return { run = function(task) return task() end }\n",
        "policy.lua": "return { attempts = 3 }\n",
      ]
    )
    let widget = directory.appending(path: "personal-clock", directoryHint: .isDirectory)
    try writePackage(
      at: widget,
      manifest: """
        manifest_version = 1
        name = "personal-clock"
        version = "0.1.0"
        kind = "widget"
        entrypoint = "widget.lua"

        [dependencies]
        retry-kit = "^1.0.0"
        """,
      files: [
        "widget.lua": "local retry = require(\"retry\")\nreturn retry\n",
        "helper.lua": "return 'private'\n",
        "assets/icon.svg": "<svg/>\n",
      ]
    )

    _ = try await install(library.path, useRegistry: false)
    let installed = try await install(widget.path, useRegistry: false)

    XCTAssertEqual(installed.map(\.name), ["personal-clock"])
    XCTAssertTrue(fileExists("active/shared/retry.lua"))
    XCTAssertTrue(fileExists("active/shared/retry/policy.lua"))
    XCTAssertTrue(fileExists("active/personal-clock/widget.lua"))
    XCTAssertTrue(fileExists("active/personal-clock/assets/icon.svg"))
    XCTAssertFalse(fileExists("active/personal-clock/helper.lua"))
    XCTAssertTrue(fileExists("store/retry-kit/1.2.0/retry.lua"))
    XCTAssertTrue(fileExists("store/personal-clock/0.1.0/helper.lua"))
    XCTAssertFalse(manualFileExists("personal-clock/widget.lua"))
    XCTAssertFalse(manualFileExists("shared/retry.lua"))

    let database = try installedDatabase()
    XCTAssertEqual(database.packages.map(\.name), ["personal-clock", "retry-kit"])
  }

  func testInstallsAHashPinnedPackageFromARegistry() async throws {
    let package = directory.appending(path: "caffeinate", directoryHint: .isDirectory)
    try writePackage(
      at: package,
      manifest: """
        manifest_version = 1
        name = "caffeinate"
        version = "1.0.0"
        kind = "widget"
        entrypoint = "widget.lua"
        """,
      files: ["widget.lua": "return nil\n"]
    )
    let archive = directory.appending(path: "caffeinate-1.0.0.tar.gz")
    try createArchive(package: package, archive: archive, files: ["package.toml", "widget.lua"])
    let digest = sha256(try Data(contentsOf: archive))
    let index = directory.appending(path: "index.json")
    try """
    {
      "registry_version": 1,
      "packages": [{
        "name": "caffeinate",
        "kind": "widget",
        "latest": "1.0.0",
        "description": "Keep macOS awake.",
        "categories": ["system"],
        "versions": [{
          "version": "1.0.0",
          "archive": "\(archive.absoluteString)",
          "sha256": "\(digest)"
        }]
      }]
    }
    """.write(to: index, atomically: true, encoding: .utf8)

    let installed = try await installer.install(
      options: WidgetPackageInstallOptions(
        source: "caffeinate",
        sha256: nil,
        registry: index.path,
        useRegistry: true,
        force: false
      )
    )

    XCTAssertEqual(installed.map(\.name), ["caffeinate"])
    XCTAssertTrue(fileExists("active/caffeinate/widget.lua"))
    XCTAssertEqual(try installedDatabase().packages.first?.version, "1.0.0")

    do {
      _ = try await installer.install(
        options: WidgetPackageInstallOptions(
          source: "caffeinate",
          sha256: nil,
          registry: index.path,
          useRegistry: true,
          force: false
        )
      )
      XCTFail("Expected the duplicate registry install to be rejected")
    } catch let error as WidgetPackageError {
      XCTAssertEqual(error, .packageAlreadyInstalled("caffeinate"))
    }
  }

  func testMigratesLegacyPackagesWithoutRemovingManualWidgets() async throws {
    let legacyPackage = legacyWidgetsDirectory.appending(
      path: ".easybar/packages/legacy-clock",
      directoryHint: .isDirectory
    )
    try writePackage(
      at: legacyPackage,
      manifest: """
        manifest_version = 1
        name = "legacy-clock"
        version = "1.0.0"
        kind = "widget"
        entrypoint = "widget.lua"

        [exports]
        retry = "retry.lua"
        """,
      files: [
        "widget.lua": "return require(\"retry\")\n",
        "retry.lua": "return { attempts = 3 }\n",
      ]
    )
    try writeFile(
      "return require(\"retry\")\n",
      at: legacyWidgetsDirectory.appending(path: "legacy-clock/widget.lua")
    )
    try writeFile(
      "return { attempts = 3 }\n",
      at: legacyWidgetsDirectory.appending(path: "shared/retry.lua")
    )
    try writeFile(
      "return 'manual'\n",
      at: legacyWidgetsDirectory.appending(path: "manual.lua")
    )

    let legacyDatabase = InstalledWidgetPackages(
      layoutVersion: 1,
      packages: [
        InstalledWidgetPackage(
          name: "legacy-clock",
          version: "1.0.0",
          kind: .widget,
          entrypoint: "widget.lua",
          dependencies: [:],
          exports: ["retry": "retry.lua"],
          source: "legacy"
        )
      ]
    )
    try writeDatabase(
      legacyDatabase,
      to: legacyWidgetsDirectory.appending(path: ".easybar/installed.json")
    )

    let package = directory.appending(path: "new-clock", directoryHint: .isDirectory)
    try writePackage(
      at: package,
      manifest: """
        manifest_version = 1
        name = "new-clock"
        version = "0.1.0"
        kind = "widget"
        entrypoint = "widget.lua"
        """,
      files: ["widget.lua": "return nil\n"]
    )

    _ = try await install(package.path, useRegistry: false)

    XCTAssertTrue(fileExists("store/legacy-clock/1.0.0/widget.lua"))
    XCTAssertTrue(fileExists("active/legacy-clock/widget.lua"))
    XCTAssertTrue(fileExists("active/shared/retry.lua"))
    XCTAssertTrue(fileExists("active/new-clock/widget.lua"))
    XCTAssertFalse(manualFileExists(".easybar"))
    XCTAssertFalse(manualFileExists("legacy-clock"))
    XCTAssertFalse(manualFileExists("shared/retry.lua"))
    XCTAssertTrue(manualFileExists("manual.lua"))
    XCTAssertEqual(try installedDatabase().layoutVersion, WidgetPackageStore.layoutVersion)
    XCTAssertEqual(
      try installedDatabase().packages.map(\.name),
      ["legacy-clock", "new-clock"]
    )
  }

  func testMigrationKeepsLegacyFilesWhenManagedStoreDoesNotContainThem() throws {
    let legacy = InstalledWidgetPackage(
      name: "legacy-clock",
      version: "1.0.0",
      kind: .widget,
      entrypoint: "widget.lua",
      dependencies: [:],
      exports: [:],
      source: "legacy"
    )
    let current = InstalledWidgetPackage(
      name: "new-clock",
      version: "0.1.0",
      kind: .widget,
      entrypoint: "widget.lua",
      dependencies: [:],
      exports: [:],
      source: "local"
    )
    try writeDatabase(
      InstalledWidgetPackages(layoutVersion: 1, packages: [legacy]),
      to: legacyWidgetsDirectory.appending(path: ".easybar/installed.json")
    )
    try writeDatabase(
      InstalledWidgetPackages(layoutVersion: WidgetPackageStore.layoutVersion, packages: [current]),
      to: packagesDirectory.appending(path: "installed.json")
    )

    XCTAssertThrowsError(
      try WidgetPackageStore.migrateLegacyInstallation(
        from: legacyWidgetsDirectory,
        to: packagesDirectory
      )
    )
    XCTAssertTrue(manualFileExists(".easybar/installed.json"))
  }

  func testDirectArchiveURLRequiresAHash() async throws {
    let package = directory.appending(path: "direct", directoryHint: .isDirectory)
    try writePackage(
      at: package,
      manifest: """
        manifest_version = 1
        name = "direct"
        version = "1.0.0"
        kind = "widget"
        entrypoint = "widget.lua"
        """,
      files: ["widget.lua": "return nil\n"]
    )
    let archive = directory.appending(path: "direct-1.0.0.tar.gz")
    try createArchive(package: package, archive: archive, files: ["package.toml", "widget.lua"])

    do {
      _ = try await install(archive.absoluteString, useRegistry: false)
      XCTFail("Expected a checksum requirement")
    } catch let error as WidgetPackageError {
      XCTAssertEqual(error, .checksumRequired(archive.absoluteString))
    }
  }

  func testRejectsInstallingAnAlreadyInstalledPackage() async throws {
    let package = directory.appending(path: "clock", directoryHint: .isDirectory)
    try writePackage(
      at: package,
      manifest: """
        manifest_version = 1
        name = "clock"
        version = "1.0.0"
        kind = "widget"
        entrypoint = "widget.lua"
        """,
      files: ["widget.lua": "return 'original'\n"]
    )
    _ = try await install(package.path, useRegistry: false)

    do {
      _ = try await install(package.path, useRegistry: false)
      XCTFail("Expected the duplicate install to be rejected")
    } catch let error as WidgetPackageError {
      XCTAssertEqual(error, .packageAlreadyInstalled("clock"))
    }

    XCTAssertEqual(try installedDatabase().packages.first?.version, "1.0.0")
    XCTAssertEqual(try managedFileContents("active/clock/widget.lua"), "return 'original'\n")
  }

  func testForceReplacesAnInstalledPackageAndRemovesItsPreviousStore() async throws {
    let original = directory.appending(path: "clock-1.0.0", directoryHint: .isDirectory)
    try writePackage(
      at: original,
      manifest: """
        manifest_version = 1
        name = "clock"
        version = "1.0.0"
        kind = "widget"
        entrypoint = "widget.lua"
        """,
      files: ["widget.lua": "return 'original'\n"]
    )
    let replacement = directory.appending(path: "clock-2.0.0", directoryHint: .isDirectory)
    try writePackage(
      at: replacement,
      manifest: """
        manifest_version = 1
        name = "clock"
        version = "2.0.0"
        kind = "widget"
        entrypoint = "widget.lua"
        """,
      files: ["widget.lua": "return 'replacement'\n"]
    )
    _ = try await install(original.path, useRegistry: false)

    let installed = try await install(replacement.path, useRegistry: false, force: true)

    XCTAssertEqual(installed.map(\.version), ["2.0.0"])
    XCTAssertEqual(try installedDatabase().packages.first?.version, "2.0.0")
    XCTAssertEqual(
      try managedFileContents("active/clock/widget.lua"),
      "return 'replacement'\n"
    )
    XCTAssertFalse(fileExists("store/clock/1.0.0"))
    XCTAssertTrue(fileExists("store/clock/2.0.0"))
    XCTAssertEqual(try replacementArtifacts(), [])
  }

  func testForceRestoresTheInstalledPackageWhenResolutionFails() async throws {
    let original = directory.appending(path: "clock", directoryHint: .isDirectory)
    try writePackage(
      at: original,
      manifest: """
        manifest_version = 1
        name = "clock"
        version = "1.0.0"
        kind = "widget"
        entrypoint = "widget.lua"
        """,
      files: ["widget.lua": "return 'original'\n"]
    )
    _ = try await install(original.path, useRegistry: false)

    var resolutionFailed = false
    do {
      _ = try await installer.install(
        options: WidgetPackageInstallOptions(
          source: "clock",
          sha256: nil,
          registry: directory.appending(path: "missing-index.json").path,
          useRegistry: true,
          force: true
        )
      )
      XCTFail("Expected registry resolution to fail")
    } catch {
      resolutionFailed = true
    }

    XCTAssertTrue(resolutionFailed)
    XCTAssertEqual(try installedDatabase().packages.first?.version, "1.0.0")
    XCTAssertEqual(try managedFileContents("active/clock/widget.lua"), "return 'original'\n")
    XCTAssertTrue(fileExists("store/clock/1.0.0/widget.lua"))
    XCTAssertEqual(try replacementArtifacts(), [])
  }

  func testCaretConstraintsFollowSemverZeroMajorRules() throws {
    let stable = try XCTUnwrap(VersionConstraint("^1.2.3"))
    let zeroMajor = try XCTUnwrap(VersionConstraint("^0.2.3"))
    XCTAssertTrue(stable.contains(try XCTUnwrap(SemanticVersion("1.9.0"))))
    XCTAssertFalse(stable.contains(try XCTUnwrap(SemanticVersion("2.0.0"))))
    XCTAssertTrue(zeroMajor.contains(try XCTUnwrap(SemanticVersion("0.2.9"))))
    XCTAssertFalse(zeroMajor.contains(try XCTUnwrap(SemanticVersion("0.3.0"))))
  }

  private func install(_ source: String, useRegistry: Bool, force: Bool = false) async throws
    -> [InstalledWidgetPackage]
  {
    try await installer.install(
      options: WidgetPackageInstallOptions(
        source: source,
        sha256: nil,
        registry: nil,
        useRegistry: useRegistry,
        force: force
      )
    )
  }

  private func writePackage(at url: URL, manifest: String, files: [String: String]) throws {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    try manifest.write(
      to: url.appending(path: "package.toml"),
      atomically: true,
      encoding: .utf8
    )
    for (relativePath, contents) in files {
      let output = url.appending(path: relativePath)
      try FileManager.default.createDirectory(
        at: output.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try contents.write(to: output, atomically: true, encoding: .utf8)
    }
  }

  private func createArchive(package: URL, archive: URL, files: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
    process.arguments = ["-czf", archive.path, "-C", package.path] + files
    try process.run()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
  }

  private func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { byte in
      let hexadecimal = String(byte, radix: 16)
      return hexadecimal.count == 1 ? "0" + hexadecimal : hexadecimal
    }.joined()
  }

  private func fileExists(_ relativePath: String) -> Bool {
    FileManager.default.fileExists(atPath: packagesDirectory.appending(path: relativePath).path)
  }

  private func manualFileExists(_ relativePath: String) -> Bool {
    FileManager.default.fileExists(
      atPath: legacyWidgetsDirectory.appending(path: relativePath).path
    )
  }

  private func managedFileContents(_ relativePath: String) throws -> String {
    try String(
      contentsOf: packagesDirectory.appending(path: relativePath),
      encoding: .utf8
    )
  }

  private func replacementArtifacts() throws -> [String] {
    try FileManager.default.contentsOfDirectory(
      atPath: packagesDirectory.deletingLastPathComponent().path
    ).filter {
      $0.hasPrefix(".easybar-packages-replacement-")
        || $0.hasPrefix(".easybar-packages-failed-")
    }
  }

  private func installedDatabase() throws -> InstalledWidgetPackages {
    try JSONDecoder().decode(
      InstalledWidgetPackages.self,
      from: Data(contentsOf: packagesDirectory.appending(path: "installed.json"))
    )
  }

  private func writeFile(_ contents: String, at url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try contents.write(to: url, atomically: true, encoding: .utf8)
  }

  private func writeDatabase(_ database: InstalledWidgetPackages, to url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    var data = try encoder.encode(database)
    data.append(0x0A)
    try data.write(to: url)
  }
}
