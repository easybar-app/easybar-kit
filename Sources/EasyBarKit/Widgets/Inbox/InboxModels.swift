import EasyBarShared
import Foundation

/// Defines the supported inbox group mode values.
enum InboxGroupMode: String, CaseIterable, Sendable {
  case source
  case date
  case category
  case severity
  case none
}

/// Defines the supported inbox sort mode values.
enum InboxSortMode: String, CaseIterable, Sendable {
  case timestamp
  case source
  case severity
  case title
}

typealias InboxSeverity = IPC.InboxSeverity

extension IPC.InboxSeverity {
  var rank: Int {
    switch self {
    case .error: 3
    case .warning: 2
    case .success: 1
    case .info: 0
    }
  }
}

/// Defines the supported inbox body format values.
enum InboxBodyFormat: String, Codable, Sendable {
  case plain
  case markdown
}

/// Stores inbox action data.
struct InboxAction: Codable, Equatable, Identifiable, Sendable {
  /// The stable identifier for this inbox action.
  let id: String
  /// The title for this inbox action.
  let title: String
  /// Whether this inbox action is enabled.
  let enabled: Bool?
  /// Whether the busy option is enabled for this inbox action.
  let busy: Bool?
  /// Whether this inbox action includes in refresh all.
  let includeInRefreshAll: Bool?
  /// The children for this inbox action.
  let children: [InboxAction]?

  /// Creates an inbox action.
  init(
    id: String,
    title: String,
    enabled: Bool? = nil,
    busy: Bool? = nil,
    includeInRefreshAll: Bool? = nil,
    children: [InboxAction]? = nil
  ) {
    self.id = id
    self.title = title
    self.enabled = enabled
    self.busy = busy
    self.includeInRefreshAll = includeInRefreshAll
    self.children = children
  }

  /// Whether this inbox action is enabled.
  var isEnabled: Bool { enabled ?? true }
  /// Whether this inbox action is busy.
  var isBusy: Bool { busy ?? false }
  /// Whether this inbox action is included in refresh all.
  var isIncludedInRefreshAll: Bool { includeInRefreshAll ?? false }
  /// Whether the has children option is enabled for this inbox action.
  var hasChildren: Bool { children?.isEmpty == false }
}

/// Stores inbox source presentation data.
struct InboxSourcePresentation: Codable, Equatable, Sendable {
  /// The name for this inbox source presentation.
  let name: String?
  /// The icon for this inbox source presentation.
  let icon: String?
  /// The color for this inbox source presentation.
  let color: String?
  /// The order for this inbox source presentation.
  let order: Int?

  /// Creates an inbox source presentation.
  init(
    name: String? = nil,
    icon: String? = nil,
    color: String? = nil,
    order: Int? = nil
  ) {
    self.name = name
    self.icon = icon
    self.color = color
    self.order = order
  }
}

/// Stores inbox item data.
struct InboxItem: Codable, Equatable, Identifiable, Sendable {
  /// The stable identifier for this inbox item.
  let id: String
  /// The title for this inbox item.
  let title: String
  /// The rendered content for this view.
  let body: String?
  /// The format for this inbox item.
  let format: InboxBodyFormat?
  /// The timestamp for this inbox item.
  let timestamp: TimeInterval?
  /// The category for this inbox item.
  let category: String?
  /// The severity for this inbox item.
  let severity: InboxSeverity?
  /// Whether this inbox item is unread.
  let unread: Bool?
  /// Whether the dismissible option is enabled for this inbox item.
  let dismissible: Bool?
  /// The actions for this inbox item.
  let actions: [InboxAction]?
  /// The source for this inbox item.
  let source: InboxSourcePresentation?
  /// The URL for this inbox item.
  let url: String?

  /// Creates an inbox item.
  init(
    id: String,
    title: String,
    body: String? = nil,
    format: InboxBodyFormat? = nil,
    timestamp: TimeInterval? = nil,
    category: String? = nil,
    severity: InboxSeverity? = nil,
    unread: Bool? = nil,
    dismissible: Bool? = nil,
    actions: [InboxAction]? = nil,
    source: InboxSourcePresentation? = nil,
    url: String? = nil
  ) {
    self.id = id
    self.title = title
    self.body = body
    self.format = format
    self.timestamp = timestamp
    self.category = category
    self.severity = severity
    self.unread = unread
    self.dismissible = dismissible
    self.actions = actions
    self.source = source
    self.url = url
  }

  /// The resolved format for this inbox item.
  var resolvedFormat: InboxBodyFormat { format ?? .plain }
  /// The resolved severity for this inbox item.
  var resolvedSeverity: InboxSeverity { severity ?? .info }
  /// Whether this inbox item is initially unread.
  var isInitiallyUnread: Bool { unread ?? true }
  /// Whether this inbox item is dismissible.
  var isDismissible: Bool { dismissible ?? true }
}

/// Stores inbox source snapshot data.
struct InboxSourceSnapshot: Codable, Equatable, Sendable {
  /// The source for this inbox source snapshot.
  let source: String
  /// The items for this inbox source snapshot.
  let items: [InboxItem]
}

/// Stores inbox source configuration data.
struct InboxSourceConfiguration: Codable, Equatable, Sendable {
  /// The source for this inbox source configuration.
  let source: String
  /// The actions for this inbox source configuration.
  let actions: [InboxAction]
  /// The order for this inbox source configuration.
  let order: Int?
  /// The presentation for this inbox source configuration.
  let presentation: InboxSourcePresentation?

  /// Creates an inbox source configuration.
  init(
    source: String,
    actions: [InboxAction],
    order: Int? = nil,
    presentation: InboxSourcePresentation? = nil
  ) {
    self.source = source
    self.actions = actions
    self.order = order
    self.presentation = presentation
  }

  /// The refresh all action for this inbox source configuration.
  var refreshAllAction: InboxAction? {
    actions.first(where: \.isIncludedInRefreshAll)
  }
}

/// Stores inbox presented item data.
struct InboxPresentedItem: Identifiable, Equatable, Sendable {
  /// The source for this inbox presented item.
  let source: String
  /// The item for this inbox presented item.
  let item: InboxItem
  /// Whether this inbox presented item is unread.
  let isUnread: Bool

  /// The stable identifier for this inbox presented item.
  var id: String { source + "\u{1f}" + item.id }
}
