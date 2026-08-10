import Foundation
import XCTest

@testable import EasyBarKit
@testable import EasyBarShared

final class FileWatcherTests: XCTestCase {
  /// Verifies that repeated atomic saves remain visible after each inode replacement.
  func testObservesMultipleAtomicFileReplacements() async throws {
    let directoryURL = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directoryURL) }

    let configURL = directoryURL.appendingPathComponent("config.toml")
    try "value = 0\n".write(to: configURL, atomically: true, encoding: .utf8)

    let watcher = makeWatcher()
    let stream = await watcher.start(configPath: configURL.path, enabled: true)
    let observations = (1...3).map {
      expectation(description: "observed atomic replacement \($0)")
    }

    let consumer = Task {
      var count = 0
      for await event in stream {
        guard case .changed = event else { continue }
        guard count < observations.count else { break }
        observations[count].fulfill()
        count += 1
        if count == observations.count { break }
      }
    }

    for value in 1...3 {
      try "value = \(value)\n".write(to: configURL, atomically: true, encoding: .utf8)
      await fulfillment(of: [observations[value - 1]], timeout: 2)
    }

    await watcher.stop()
    consumer.cancel()
  }

  /// Verifies that a missing config can be created and then atomically replaced.
  func testMovesFromParentDirectoryWatchToCreatedConfigFile() async throws {
    let directoryURL = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directoryURL) }

    let configURL = directoryURL.appendingPathComponent("config.toml")
    let watcher = makeWatcher()
    let stream = await watcher.start(configPath: configURL.path, enabled: true)
    let creationObserved = expectation(description: "observed creation")
    let replacementObserved = expectation(description: "observed replacement")

    let consumer = Task {
      var count = 0
      for await event in stream {
        guard case .changed = event else { continue }
        if count == 0 {
          creationObserved.fulfill()
        } else {
          replacementObserved.fulfill()
        }
        count += 1
        if count == 2 { break }
      }
    }

    try "value = 1\n".write(to: configURL, atomically: true, encoding: .utf8)
    await fulfillment(of: [creationObserved], timeout: 2)
    try "value = 2\n".write(to: configURL, atomically: true, encoding: .utf8)

    await fulfillment(of: [replacementObserved], timeout: 2)
    await watcher.stop()
    consumer.cancel()
  }

  /// Verifies that stopping the actor finishes the active event stream.
  func testStopFinishesActiveStream() async throws {
    let directoryURL = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directoryURL) }

    let configURL = directoryURL.appendingPathComponent("config.toml")
    try "value = 0\n".write(to: configURL, atomically: true, encoding: .utf8)

    let watcher = makeWatcher()
    let stream = await watcher.start(configPath: configURL.path, enabled: true)
    let finished = expectation(description: "stream finished")

    let consumer = Task {
      for await _ in stream {}
      finished.fulfill()
    }

    await watcher.stop()

    await fulfillment(of: [finished], timeout: 1)
    consumer.cancel()
  }

  private func makeWatcher() -> FileWatcher {
    FileWatcher(
      logger: ProcessLogger(
        label: "file-watcher.tests",
        minimumLevel: .error,
        outputStream: nil,
        errorStream: nil
      )
    )
  }

  private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("easybar-file-watcher-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
}
