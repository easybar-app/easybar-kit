import Darwin
import EasyBarShared
import Foundation
import XCTest

@testable import EasyBarKit

class ConfigLoaderTestCase: XCTestCase {
  let environmentKeys = [
    SharedEnvironmentKeys.configPath,
    SharedEnvironmentKeys.runtimeDirectory,
    SharedEnvironmentKeys.loggingLevel,
  ]

  var originalEnvironment: [String: String?] = [:]
  var originalSnapshot: ConfigSnapshot!
  var tempDirectoryURL: URL!

  /// Prepares isolated state before each test.
  override func setUpWithError() throws {
    try super.setUpWithError()

    originalEnvironment = environmentKeys.reduce(into: [:]) { result, key in
      result[key] = ProcessInfo.processInfo.environment[key]
    }
    for key in environmentKeys {
      setEnvironmentValue(nil, for: key)
    }

    tempDirectoryURL = try makeTemporaryDirectory()
    setEnvironmentValue(
      tempDirectoryURL.appendingPathComponent("runtime", isDirectory: true).path,
      for: SharedEnvironmentKeys.runtimeDirectory
    )

    let config = Config.makeUnloadedConfig()
    originalSnapshot = config.snapshot()

    try copyThemeFixtures(
      to: tempDirectoryURL.appendingPathComponent("themes", isDirectory: true)
    )
  }

  /// Restores state mutated by the test fixture.
  override func tearDownWithError() throws {
    restoreEnvironment()

    let config = Config.makeUnloadedConfig()
    config.apply(originalSnapshot)
    config.resetRegisteredDirectories()

    if let tempDirectoryURL {
      try? FileManager.default.removeItem(at: tempDirectoryURL)
    }

    try super.tearDownWithError()
  }
}

extension ConfigLoaderTestCase {
  /// Creates an isolated temporary directory for file-system assertions.
  func makeTemporaryDirectory() throws -> URL {
    let directoryURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("easybar-config-tests-\(UUID().uuidString)", isDirectory: true)

    try FileManager.default.createDirectory(
      at: directoryURL,
      withIntermediateDirectories: true
    )

    return directoryURL
  }

  /// Returns the repository root URL.
  func repoRootURL() -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  /// Copies bundled theme fixtures into a test-local themes directory.
  func copyThemeFixtures(to destinationURL: URL) throws {
    let sourceURL = repoRootURL().appendingPathComponent("themes", isDirectory: true)

    if FileManager.default.fileExists(atPath: destinationURL.path) {
      try FileManager.default.removeItem(at: destinationURL)
    }

    try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
  }

  /// Writes a TOML fixture to the current test config path.
  func writeConfig(_ content: String, to url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try content.write(to: url, atomically: true, encoding: .utf8)
  }

  /// Sets or clears one environment variable while preserving its original value.
  func setEnvironmentValue(_ value: String?, for key: String) {
    if let value {
      setenv(key, value, 1)
    } else {
      unsetenv(key)
    }
  }

  /// Escapes a string so it can be embedded in a TOML basic string.
  func tomlEscaped(_ value: String) -> String {
    value
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
  }

  /// Restores environment variables captured before the test.
  func restoreEnvironment() {
    for key in environmentKeys {
      setEnvironmentValue(originalEnvironment[key] ?? nil, for: key)
    }
  }
}
