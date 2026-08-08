import CryptoKit
import EasyBarShared
import Foundation
import XCTest

@testable import EasyBarCtl

final class WidgetPackageInstallerTests: XCTestCase {
  private var directory: URL!
  private var widgetsDirectory: URL!
  private var installer: WidgetPackageInstaller!

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory.appending(
      path: "easybar-package-tests-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    widgetsDirectory = directory.appending(path: "widgets", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    installer = WidgetPackageInstaller(
      logger: ProcessLogger(label: "package-tests", minimumLevel: .error)
    )
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
    directory = nil
    widgetsDirectory = nil
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
    XCTAssertTrue(fileExists("shared/retry.lua"))
    XCTAssertTrue(fileExists("shared/retry/policy.lua"))
    XCTAssertTrue(fileExists("personal-clock/widget.lua"))
    XCTAssertTrue(fileExists("personal-clock/assets/icon.svg"))
    XCTAssertFalse(fileExists("personal-clock/helper.lua"))
    XCTAssertTrue(fileExists(".easybar/packages/retry-kit/retry.lua"))
    XCTAssertTrue(fileExists(".easybar/packages/personal-clock/helper.lua"))

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
        "latest": "1.0.0",
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
        widgetsDirectory: widgetsDirectory.path,
        useRegistry: true
      )
    )

    XCTAssertEqual(installed.map(\.name), ["caffeinate"])
    XCTAssertTrue(fileExists("caffeinate/widget.lua"))
    XCTAssertEqual(try installedDatabase().packages.first?.version, "1.0.0")
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

  func testCaretConstraintsFollowSemverZeroMajorRules() throws {
    let stable = try XCTUnwrap(VersionConstraint("^1.2.3"))
    let zeroMajor = try XCTUnwrap(VersionConstraint("^0.2.3"))
    XCTAssertTrue(stable.contains(try XCTUnwrap(SemanticVersion("1.9.0"))))
    XCTAssertFalse(stable.contains(try XCTUnwrap(SemanticVersion("2.0.0"))))
    XCTAssertTrue(zeroMajor.contains(try XCTUnwrap(SemanticVersion("0.2.9"))))
    XCTAssertFalse(zeroMajor.contains(try XCTUnwrap(SemanticVersion("0.3.0"))))
  }

  private func install(_ source: String, useRegistry: Bool) async throws
    -> [InstalledWidgetPackage]
  {
    try await installer.install(
      options: WidgetPackageInstallOptions(
        source: source,
        sha256: nil,
        registry: nil,
        widgetsDirectory: widgetsDirectory.path,
        useRegistry: useRegistry
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
    FileManager.default.fileExists(atPath: widgetsDirectory.appending(path: relativePath).path)
  }

  private func installedDatabase() throws -> InstalledWidgetPackages {
    try JSONDecoder().decode(
      InstalledWidgetPackages.self,
      from: Data(contentsOf: widgetsDirectory.appending(path: ".easybar/installed.json"))
    )
  }
}
