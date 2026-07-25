import Foundation

/// Reads retained EasyBar process logs and follows active files across rotation.
public enum ProcessLogStore {
  private static let sourcesByFileName = [
    "easybar.out": "easybar",
    "calendar-agent.out": "calendar-agent",
    "network-agent.out": "network-agent",
  ]

  /// Returns whether at least one known active or rotated log file exists.
  public static func hasLogs(in directory: String) -> Bool {
    !discoveredFiles(in: directory).isEmpty
  }

  /// Loads matching retained history in chronological order.
  public static func history(
    in directory: String,
    filter: ProcessLogFilter,
    limit: Int?
  ) throws -> [ProcessLogRecord] {
    let files = discoveredFiles(in: directory)
    if let limit {
      return try boundedHistory(files: files, filter: filter, limit: max(0, limit))
    }

    var sequenced: [(sequence: Int, record: ProcessLogRecord)] = []
    var sequence = 0

    for file in files {
      let contents = try String(contentsOf: file.url, encoding: .utf8)
      for line in contents.split(separator: "\n", omittingEmptySubsequences: true) {
        guard filter.mightMatch(rawLine: line) else { continue }
        let record = ProcessLogRecord.parse(String(line), source: file.source)
        if filter.matches(record) {
          sequenced.append((sequence, record))
        }
        sequence += 1
      }
    }

    sequenced.sort { lhs, rhs in
      switch (lhs.record.timestamp, rhs.record.timestamp) {
      case (.some(let left), .some(let right)) where left != right:
        return left < right
      default:
        return lhs.sequence < rhs.sequence
      }
    }

    return sequenced.map(\.record)
  }

  /// Reads newest files first and stops once each process has enough candidates.
  private static func boundedHistory(
    files: [DiscoveredProcessLogFile],
    filter: ProcessLogFilter,
    limit: Int
  ) throws -> [ProcessLogRecord] {
    guard limit > 0 else { return [] }
    var records: [ProcessLogRecord] = []

    for (_, processFiles) in Dictionary(grouping: files, by: \.source) {
      var processRecords: [ProcessLogRecord] = []
      for file in processFiles.sorted(by: { $0.archiveIndex < $1.archiveIndex }) {
        try ReverseLineReader.forEachLine(at: file.url) { lineData in
          guard let line = String(data: lineData, encoding: .utf8) else {
            throw CocoaError(
              .fileReadInapplicableStringEncoding,
              userInfo: [NSFilePathErrorKey: file.url.path]
            )
          }
          guard filter.mightMatch(rawLine: Substring(line)) else { return true }

          let record = ProcessLogRecord.parse(line, source: file.source)
          guard filter.matches(record) else { return true }

          processRecords.append(record)
          return processRecords.count < limit
        }
        if processRecords.count == limit { break }
      }
      records.append(contentsOf: processRecords)
    }

    records.sort(by: chronologicalOrder)
    return Array(records.suffix(limit))
  }

  private static func chronologicalOrder(
    _ lhs: ProcessLogRecord,
    _ rhs: ProcessLogRecord
  ) -> Bool {
    switch (lhs.timestamp, rhs.timestamp) {
    case (.some(let left), .some(let right)) where left != right:
      return left < right
    case (.none, .some):
      return true
    default:
      return false
    }
  }

  fileprivate static func discoveredFiles(in directory: String) -> [DiscoveredProcessLogFile] {
    let directoryURL = URL(fileURLWithPath: directory, isDirectory: true)
    guard
      let names = try? FileManager.default.contentsOfDirectory(atPath: directoryURL.path)
    else { return [] }

    return sourcesByFileName.flatMap { baseName, source in
      names.compactMap { name -> DiscoveredProcessLogFile? in
        guard let archive = archiveIndex(name: name, baseName: baseName) else { return nil }
        let url = directoryURL.appendingPathComponent(name)
        guard let identity = fileIdentity(at: url) else { return nil }
        return DiscoveredProcessLogFile(
          url: url,
          source: source,
          archiveIndex: archive,
          identity: identity
        )
      }
      .sorted { lhs, rhs in
        if lhs.archiveIndex != rhs.archiveIndex {
          return lhs.archiveIndex > rhs.archiveIndex
        }
        return lhs.url.lastPathComponent < rhs.url.lastPathComponent
      }
    }
  }

  private static func archiveIndex(name: String, baseName: String) -> Int? {
    if name == baseName { return 0 }
    let prefix = "\(baseName)."
    guard name.hasPrefix(prefix) else { return nil }
    let suffix = name.dropFirst(prefix.count)
    guard let index = Int(suffix), index > 0 else { return nil }
    return index
  }

  private static func fileIdentity(at url: URL) -> ProcessLogFileIdentity? {
    guard
      let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
      let device = attributes[.systemNumber] as? NSNumber,
      let inode = attributes[.systemFileNumber] as? NSNumber
    else { return nil }

    return ProcessLogFileIdentity(
      device: device.uint64Value,
      inode: inode.uint64Value
    )
  }
}

/// Polling follower that survives the logger's rename-based file rotation.
public final class ProcessLogFollower {
  private struct State {
    var url: URL
    var source: String
    var offset: UInt64
    var pendingLineData: Data
  }

  private let directory: String
  private let filter: ProcessLogFilter
  private var states: [ProcessLogFileIdentity: State] = [:]

  /// Captures current file ends so subsequent polls emit only new records.
  public init(directory: String, filter: ProcessLogFilter) {
    self.directory = directory
    self.filter = filter

    for file in ProcessLogStore.discoveredFiles(in: directory) {
      states[file.identity] = State(
        url: file.url,
        source: file.source,
        offset: fileSize(at: file.url),
        pendingLineData: Data()
      )
    }
  }

  /// Reads newly appended complete lines from active and newly rotated files.
  public func poll() -> [ProcessLogRecord] {
    var records: [(sequence: Int, record: ProcessLogRecord)] = []
    var sequence = 0

    for file in ProcessLogStore.discoveredFiles(in: directory) {
      var state =
        states[file.identity]
        ?? State(url: file.url, source: file.source, offset: 0, pendingLineData: Data())
      state.url = file.url
      state.source = file.source

      let size = fileSize(at: file.url)
      if size < state.offset {
        state.offset = 0
        state.pendingLineData.removeAll(keepingCapacity: true)
      }

      guard size > state.offset else {
        states[file.identity] = state
        continue
      }

      guard let data = readData(at: file.url, offset: state.offset) else {
        states[file.identity] = state
        continue
      }
      state.offset += UInt64(data.count)

      let combined = state.pendingLineData + data
      var lineStart = combined.startIndex

      for newlineIndex in combined.indices where combined[newlineIndex] == 0x0A {
        let lineData = combined[lineStart..<newlineIndex]
        lineStart = combined.index(after: newlineIndex)
        guard !lineData.isEmpty else { continue }

        let line = String(decoding: lineData, as: UTF8.self)
        guard filter.mightMatch(rawLine: Substring(line)) else { continue }
        let record = ProcessLogRecord.parse(line, source: state.source)
        if filter.matches(record) {
          records.append((sequence, record))
        }
        sequence += 1
      }

      state.pendingLineData = Data(combined[lineStart...])

      states[file.identity] = state
    }

    records.sort { lhs, rhs in
      switch (lhs.record.timestamp, rhs.record.timestamp) {
      case (.some(let left), .some(let right)) where left != right:
        return left < right
      default:
        return lhs.sequence < rhs.sequence
      }
    }
    return records.map(\.record)
  }
}

private struct ProcessLogFileIdentity: Hashable {
  let device: UInt64
  let inode: UInt64
}

private struct DiscoveredProcessLogFile {
  let url: URL
  let source: String
  let archiveIndex: Int
  let identity: ProcessLogFileIdentity
}

private func fileSize(at url: URL) -> UInt64 {
  guard
    let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
    let size = attributes[.size] as? NSNumber
  else { return 0 }
  return size.uint64Value
}

private func readData(at url: URL, offset: UInt64) -> Data? {
  guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
  defer { try? handle.close() }

  do {
    try handle.seek(toOffset: offset)
    return try handle.readToEnd() ?? Data()
  } catch {
    return nil
  }
}
