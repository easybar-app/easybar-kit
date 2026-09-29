import Foundation

/// Errors produced while framing newline-delimited JSON messages.
public enum LineDelimitedJSONDecoderError: Error, CustomStringConvertible, Equatable {
  case lineTooLong(maxLineBytes: Int)

  public var description: String {
    switch self {
    case .lineTooLong(let maxLineBytes):
      return "line exceeded maximum size of \(maxLineBytes) bytes"
    }
  }
}

/// Incrementally decodes newline-delimited JSON messages from arbitrary byte chunks.
public struct LineDelimitedJSONDecoder<Message: Decodable> {
  /// The default max line bytes for this line delimited JSON decoder.
  public static var defaultMaxLineBytes: Int { 1_048_576 }

  /// The pending for this line delimited JSON decoder.
  private var pending = Data()
  /// Whether the discarding oversized line option is enabled for this line delimited JSON decoder.
  private var discardingOversizedLine = false
  /// The decoder for this line delimited JSON decoder.
  private let decoder: JSONDecoder
  /// The max line bytes for this line delimited JSON decoder.
  private let maxLineBytes: Int

  /// Creates a new line-delimited decoder.
  public init(
    decoder: JSONDecoder? = nil,
    maxLineBytes: Int = LineDelimitedJSONDecoder.defaultMaxLineBytes
  ) {
    self.decoder = decoder ?? Self.makeDefaultDecoder()
    self.maxLineBytes = max(1, maxLineBytes)
  }

  /// Appends bytes and returns one result for each complete non-empty line.
  public mutating func append(_ bytes: ArraySlice<UInt8>) -> [Result<Message, Error>] {
    pending.append(contentsOf: bytes)
    return decodePendingLines()
  }

  /// Decodes a final unterminated non-empty line, when one is pending.
  public mutating func flush() -> [Result<Message, Error>] {
    if discardingOversizedLine {
      pending.removeAll(keepingCapacity: false)
      discardingOversizedLine = false
      return []
    }

    guard !pending.isEmpty else { return [] }

    let line = pending
    pending.removeAll(keepingCapacity: false)

    guard line.count <= maxLineBytes else {
      return [.failure(LineDelimitedJSONDecoderError.lineTooLong(maxLineBytes: maxLineBytes))]
    }

    return [decode(line)]
  }

  /// Decodes pending lines.
  private mutating func decodePendingLines() -> [Result<Message, Error>] {
    var results: [Result<Message, Error>] = []

    while let newlineIndex = pending.firstIndex(of: 0x0A) {
      let line = pending.prefix(upTo: newlineIndex)
      pending.removeSubrange(...newlineIndex)

      if discardingOversizedLine {
        discardingOversizedLine = false
        continue
      }

      guard !line.isEmpty else { continue }
      guard line.count <= maxLineBytes else {
        results.append(.failure(LineDelimitedJSONDecoderError.lineTooLong(maxLineBytes: maxLineBytes)))
        continue
      }

      results.append(decode(line))
    }

    if pending.count > maxLineBytes {
      pending.removeAll(keepingCapacity: false)
      discardingOversizedLine = true
      results.append(.failure(LineDelimitedJSONDecoderError.lineTooLong(maxLineBytes: maxLineBytes)))
    }

    return results
  }

  /// Decodes the requested operation.
  private func decode(_ data: Data.SubSequence) -> Result<Message, Error> {
    do {
      return .success(try decoder.decode(Message.self, from: Data(data)))
    } catch {
      return .failure(error)
    }
  }

  /// Creates default decoder.
  private static func makeDefaultDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}
