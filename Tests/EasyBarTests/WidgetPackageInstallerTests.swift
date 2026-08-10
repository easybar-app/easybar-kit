import CryptoKit
import EasyBarShared
import Foundation
import XCTest

@testable import EasyBarCtl

final class WidgetPackageInstallerTests: XCTestCase {
  private var directory: URL!
  private var packagesDirectory: URL!
  private var installer: WidgetPackageInstaller!

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory.appending(
      path: "easybar-package-tests-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    packagesDirectory = directory.appending(path: "data/packages", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    installer = WidgetPackageInstaller(
      logger: ProcessLogger(label: "package-tests", minimumLevel: .error),
      packagesDirectory: packagesDirectory
    )
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
    directory = nil
    packagesDirectory = nil
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
    XCTAssertTrue(fileExists("store/retry-kit/1.2.0/.easybar/source/retry.lua"))
    XCTAssertTrue(fileExists("store/personal-clock/0.1.0/.easybar/source/helper.lua"))
    XCTAssertEqual(
      try symbolicLinkDestination("active/personal-clock"),
      "../store/personal-clock/0.1.0"
    )

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

  func testRejectsOlderPackageStoreLayouts() async throws {
    try """
    {
      "layout_version": 2,
      "packages": []
    }
    """.write(
      to: packagesDirectory.appending(path: "installed.json"),
      atomically: true,
      encoding: .utf8
    )

    do {
      _ = try await install("clock", useRegistry: false)
      XCTFail("Expected the old package store layout to be rejected")
    } catch let error as WidgetPackageError {
      XCTAssertEqual(error, .installConflict("unsupported installed package layout"))
    }
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

  func testForceReplacesAnInstalledPackageAndRetainsItsPreviousStore() async throws {
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
    XCTAssertTrue(fileExists("store/clock/1.0.0"))
    XCTAssertTrue(fileExists("store/clock/2.0.0"))
    XCTAssertEqual(try symbolicLinkDestination("active/clock"), "../store/clock/2.0.0")
    XCTAssertEqual(try replacementArtifacts(), [])
  }

  func testForceReinstallsTheSameVersionThroughStaging() async throws {
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

    try "return 'replacement'\n".write(
      to: package.appending(path: "widget.lua"),
      atomically: true,
      encoding: .utf8
    )
    _ = try await install(package.path, useRegistry: false, force: true)

    XCTAssertEqual(try installedDatabase().packages.first?.version, "1.0.0")
    XCTAssertEqual(try managedFileContents("active/clock/widget.lua"), "return 'replacement'\n")
    XCTAssertEqual(
      try managedFileContents("store/clock/1.0.0/.easybar/source/widget.lua"),
      "return 'replacement'\n"
    )
    XCTAssertEqual(try symbolicLinkDestination("active/clock"), "../store/clock/1.0.0")
    XCTAssertEqual(try replacementArtifacts(), [])
  }

  func testPackageStoreKeepsTheActiveVersionAndTwoPreviousVersions() async throws {
    for version in ["1.0.0", "1.1.0", "1.2.0", "1.3.0"] {
      let package = directory.appending(path: "clock-\(version)", directoryHint: .isDirectory)
      try writePackage(
        at: package,
        manifest: """
          manifest_version = 1
          name = "clock"
          version = "\(version)"
          kind = "widget"
          entrypoint = "widget.lua"
          """,
        files: ["widget.lua": "return '\(version)'\n"]
      )
      _ = try await install(
        package.path,
        useRegistry: false,
        force: version != "1.0.0"
      )
    }

    XCTAssertFalse(fileExists("store/clock/1.0.0"))
    XCTAssertTrue(fileExists("store/clock/1.1.0"))
    XCTAssertTrue(fileExists("store/clock/1.2.0"))
    XCTAssertTrue(fileExists("store/clock/1.3.0"))
    XCTAssertEqual(try symbolicLinkDestination("active/clock"), "../store/clock/1.3.0")
    XCTAssertEqual(try replacementArtifacts(), [])
  }

  func testForceLeavesTheInstalledPackageUntouchedWhenResolutionFails() async throws {
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

  func testForceRollsBackTheStoreWhenActivationFails() async throws {
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

    let activeDirectory = packagesDirectory.appending(path: "active", directoryHint: .isDirectory)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o555],
      ofItemAtPath: activeDirectory.path
    )
    defer {
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: activeDirectory.path
      )
    }

    do {
      _ = try await install(replacement.path, useRegistry: false, force: true)
      XCTFail("Expected activation to fail")
    } catch {
      // The active directory is intentionally read-only for this replacement attempt.
    }

    XCTAssertEqual(try installedDatabase().packages.first?.version, "1.0.0")
    XCTAssertEqual(try managedFileContents("active/clock/widget.lua"), "return 'original'\n")
    XCTAssertTrue(fileExists("store/clock/1.0.0"))
    XCTAssertFalse(fileExists("store/clock/2.0.0"))
    XCTAssertEqual(try symbolicLinkDestination("active/clock"), "../store/clock/1.0.0")
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

  private func symbolicLinkDestination(_ relativePath: String) throws -> String {
    try FileManager.default.destinationOfSymbolicLink(
      atPath: packagesDirectory.appending(path: relativePath).path
    )
  }

  private func managedFileContents(_ relativePath: String) throws -> String {
    try String(
      contentsOf: packagesDirectory.appending(path: relativePath),
      encoding: .utf8
    )
  }

  private func replacementArtifacts() throws -> [String] {
    guard let enumerator = FileManager.default.enumerator(atPath: packagesDirectory.path) else {
      return []
    }
    return enumerator.compactMap { $0 as? String }.filter {
      $0.contains(".staging-") || $0.contains(".backup-")
    }.sorted()
  }

  private func installedDatabase() throws -> InstalledWidgetPackages {
    try JSONDecoder().decode(
      InstalledWidgetPackages.self,
      from: Data(contentsOf: packagesDirectory.appending(path: "installed.json"))
    )
  }

}
