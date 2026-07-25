import Foundation

/// Statistics returned by a reverse line scan.
struct ReverseLineReadStats: Equatable, Sendable {
  let fileSize: UInt64
  let bytesRead: UInt64
}

/// Reads newline-delimited files from the end without loading the complete file into memory.
enum ReverseLineReader {
  static let defaultChunkSize = 64 * 1024

  /// Visits non-empty lines from newest to oldest.
  ///
  /// Return `false` from `body` to stop before older file contents are read.
  @discardableResult
  static func forEachLine(
    at url: URL,
    chunkSize: Int = defaultChunkSize,
    body: (Data) throws -> Bool
  ) throws -> ReverseLineReadStats {
    precondition(chunkSize > 0, "Reverse line reader chunk size must be positive")

    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }

    let fileSize = try handle.seekToEnd()
    var offset = fileSize
    var pendingFragments: [Data] = []
    var pendingByteCount = 0
    var bytesRead: UInt64 = 0

    func visitLine(prefix: Data) throws -> Bool {
      let lineByteCount = prefix.count + pendingByteCount
      guard lineByteCount > 0 else { return true }

      var line = Data(capacity: lineByteCount)
      line.append(prefix)
      for fragment in pendingFragments.reversed() {
        line.append(fragment)
      }
      pendingFragments.removeAll(keepingCapacity: true)
      pendingByteCount = 0
      return try body(line)
    }

    while offset > 0 {
      let requestedCount = Int(min(UInt64(chunkSize), offset))
      offset -= UInt64(requestedCount)
      try handle.seek(toOffset: offset)

      let chunk = try readExactly(requestedCount, from: handle)
      guard !chunk.isEmpty else { break }
      bytesRead += UInt64(chunk.count)

      var lineEnd = chunk.endIndex
      for newlineIndex in chunk.indices.reversed() where chunk[newlineIndex] == 0x0A {
        let lineStart = chunk.index(after: newlineIndex)
        let prefix = Data(chunk[lineStart..<lineEnd])
        if try !visitLine(prefix: prefix) {
          return ReverseLineReadStats(fileSize: fileSize, bytesRead: bytesRead)
        }
        lineEnd = newlineIndex
      }

      if lineEnd > chunk.startIndex {
        let fragment = Data(chunk[chunk.startIndex..<lineEnd])
        pendingFragments.append(fragment)
        pendingByteCount += fragment.count
      }
    }

    if pendingByteCount > 0 {
      _ = try visitLine(prefix: Data())
    }

    return ReverseLineReadStats(fileSize: fileSize, bytesRead: bytesRead)
  }

  private static func readExactly(
    _ requestedCount: Int,
    from handle: FileHandle
  ) throws -> Data {
    var result = Data()
    result.reserveCapacity(requestedCount)

    while result.count < requestedCount {
      let remaining = requestedCount - result.count
      guard let data = try handle.read(upToCount: remaining), !data.isEmpty else { break }
      result.append(data)
    }

    return result
  }
}
