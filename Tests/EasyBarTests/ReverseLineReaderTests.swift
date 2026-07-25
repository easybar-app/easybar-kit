import Foundation
import XCTest

@testable import EasyBarShared

final class ReverseLineReaderTests: XCTestCase {
  func testReadsNewestLinesAcrossChunkAndUTF8Boundaries() throws {
    let file = try makeTemporaryFile(
      containing: Data("alpha\nβeta\nthird line without newline".utf8)
    )
    defer { try? FileManager.default.removeItem(at: file) }

    var lines: [String] = []
    try ReverseLineReader.forEachLine(at: file, chunkSize: 31) { lineData in
      lines.append(try XCTUnwrap(String(data: lineData, encoding: .utf8)))
      return true
    }

    XCTAssertEqual(lines, ["third line without newline", "βeta", "alpha"])
  }

  func testSkipsEmptyLinesLikeForwardHistoryReader() throws {
    let file = try makeTemporaryFile(containing: Data("first\n\nsecond\n\n".utf8))
    defer { try? FileManager.default.removeItem(at: file) }

    var lines: [String] = []
    try ReverseLineReader.forEachLine(at: file, chunkSize: 3) { lineData in
      lines.append(String(decoding: lineData, as: UTF8.self))
      return true
    }

    XCTAssertEqual(lines, ["second", "first"])
  }

  func testStopsBeforeReadingOlderFileContents() throws {
    var contents = Data(repeating: 0x78, count: 512 * 1024)
    contents.append(Data("\nnewest\n".utf8))
    let file = try makeTemporaryFile(containing: contents)
    defer { try? FileManager.default.removeItem(at: file) }

    var lines: [String] = []
    let stats = try ReverseLineReader.forEachLine(at: file, chunkSize: 4096) { lineData in
      lines.append(String(decoding: lineData, as: UTF8.self))
      return false
    }

    XCTAssertEqual(lines, ["newest"])
    XCTAssertEqual(stats.fileSize, UInt64(contents.count))
    XCTAssertLessThanOrEqual(stats.bytesRead, 4096)
    XCTAssertLessThan(stats.bytesRead, stats.fileSize)
  }

  private func makeTemporaryFile(containing data: Data) throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("easybar-reverse-lines-\(UUID().uuidString)")
    try data.write(to: url)
    return url
  }
}
