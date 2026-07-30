import Foundation
import XCTest

final class BuildScriptSafetyTests: XCTestCase {
  func testCleanDistAcceptsOnlyRepositoryRootDistributionDirectories() throws {
    for path in ["dist", "./dist", "dist-debug", "dist_custom"] {
      XCTAssertEqual(
        try runCleaner(arguments: ["--check", path]),
        0,
        "Expected \(path) to be accepted"
      )
    }

    for path in [".", "Sources", ".build", "nested/dist", "/tmp/easybar-dist"] {
      XCTAssertEqual(
        try runCleaner(arguments: ["--check", path]),
        2,
        "Expected \(path) to be rejected"
      )
    }
  }

  func testCleanDistRemovesValidatedDirectory() throws {
    let directoryName = "dist-safety-test-\(UUID().uuidString)"
    let directoryURL = repositoryRoot.appendingPathComponent(directoryName, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directoryURL) }

    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: false)
    try Data("sentinel".utf8).write(to: directoryURL.appendingPathComponent("sentinel"))

    XCTAssertEqual(try runCleaner(arguments: [directoryName]), 0)
    XCTAssertFalse(FileManager.default.fileExists(atPath: directoryURL.path))
  }

  private var repositoryRoot: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  private func runCleaner(arguments: [String]) throws -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments =
      [
        repositoryRoot.appendingPathComponent("scripts/build/clean-dist-dir.sh").path
      ] + arguments
    process.currentDirectoryURL = repositoryRoot
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    return process.terminationStatus
  }
}
