import Foundation
import XCTest

@testable import EasyBarShared

final class ProcessLogFollowerHardeningTests: XCTestCase {
  func testFollowerPreservesUTF8ScalarSplitAcrossPolls() throws {
    let directory = try makeProcessLogDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let active = directory.appendingPathComponent("easybar.out")
    try write(
      "[2026-07-21T20:00:00.000+02:00] [INFO ] existing\n",
      to: active
    )

    let follower = ProcessLogFollower(directory: directory.path, filter: ProcessLogFilter())
    let scalar = Data("🔒".utf8)
    var firstChunk = Data("[2026-07-21T20:01:00.000+02:00] [INFO ] split ".utf8)
    firstChunk.append(contentsOf: scalar.prefix(2))
    try append(firstChunk, to: active)
    XCTAssertTrue(follower.poll().isEmpty)

    var secondChunk = Data(scalar.dropFirst(2))
    secondChunk.append(0x0A)
    try append(secondChunk, to: active)
    XCTAssertEqual(follower.poll().map(\.message), ["split 🔒"])
  }
}

private func makeProcessLogDirectory() throws -> URL {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("easybar-process-log-hardening-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory
}

private func write(_ text: String, to url: URL) throws {
  try text.write(to: url, atomically: true, encoding: .utf8)
}

private func append(_ data: Data, to url: URL) throws {
  let handle = try FileHandle(forWritingTo: url)
  defer { try? handle.close() }
  try handle.seekToEnd()
  try handle.write(contentsOf: data)
}
