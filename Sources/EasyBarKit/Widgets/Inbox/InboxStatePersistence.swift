import EasyBarShared
import Foundation

/// Stores inbox persisted state data.
struct InboxPersistedState: Codable, Equatable {
  /// The read item IDs for this inbox persisted state.
  var readItemIDs: Set<String> = []
  /// The unread item IDs for this inbox persisted state.
  var unreadItemIDs: Set<String> = []
  /// The dismissed item IDs for this inbox persisted state.
  var dismissedItemIDs: Set<String> = []

  /// Maps stored properties to their encoded keys.
  private enum CodingKeys: String, CodingKey {
    case readItemIDs
    case unreadItemIDs
    case dismissedItemIDs
  }

  /// Creates an inbox persisted state.
  init(
    readItemIDs: Set<String> = [],
    unreadItemIDs: Set<String> = [],
    dismissedItemIDs: Set<String> = []
  ) {
    self.readItemIDs = readItemIDs
    self.unreadItemIDs = unreadItemIDs
    self.dismissedItemIDs = dismissedItemIDs
  }

  /// Creates an inbox persisted state.
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    readItemIDs = Set(try container.decodeIfPresent([String].self, forKey: .readItemIDs) ?? [])
    unreadItemIDs = Set(try container.decodeIfPresent([String].self, forKey: .unreadItemIDs) ?? [])
    dismissedItemIDs = Set(
      try container.decodeIfPresent([String].self, forKey: .dismissedItemIDs) ?? [])
  }

  /// Encodes the requested value.
  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(readItemIDs.sorted(), forKey: .readItemIDs)
    try container.encode(unreadItemIDs.sorted(), forKey: .unreadItemIDs)
    try container.encode(dismissedItemIDs.sorted(), forKey: .dismissedItemIDs)
  }
}

/// Stores inbox state persistence data.
struct InboxStatePersistence {
  /// The file URL for this inbox state persistence.
  let fileURL: URL
  /// The logger used to record operational diagnostics.
  let logger: ProcessLogger

  /// Loads the requested value.
  func load() -> InboxPersistedState {
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return .init() }
    do {
      let data = try Data(contentsOf: fileURL)
      return try JSONDecoder().decode(InboxPersistedState.self, from: data)
    } catch {
      logger.error(
        "failed to load inbox state",
        .field("path", fileURL.path),
        .field("error", error)
      )
      return .init()
    }
  }

  /// Saves the requested operation.
  func save(_ state: InboxPersistedState) {
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
      var data = try encoder.encode(state)
      data.append(0x0A)
      let directory = fileURL.deletingLastPathComponent()
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      try data.write(to: fileURL, options: .atomic)
    } catch {
      logger.error(
        "failed to save inbox state",
        .field("path", fileURL.path),
        .field("error", error)
      )
    }
  }
}
