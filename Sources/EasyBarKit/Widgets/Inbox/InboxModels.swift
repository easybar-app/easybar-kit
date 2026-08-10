import Foundation

enum InboxGroupMode: String, CaseIterable, Sendable {
  case source
  case date
  case category
  case severity
  case none
}

enum InboxSortMode: String, CaseIterable, Sendable {
  case timestamp
  case source
  case severity
  case title
}

enum InboxSeverity: String, Codable, CaseIterable, Sendable {
  case info
  case success
  case warning
  case error

  var rank: Int {
    switch self {
    case .error: 3
    case .warning: 2
    case .success: 1
    case .info: 0
    }
  }
}

enum InboxBodyFormat: String, Codable, Sendable {
  case plain
  case markdown
}

struct InboxAction: Codable, Equatable, Identifiable, Sendable {
  let id: String
  let title: String
  let enabled: Bool?
  let busy: Bool?
  let includeInRefreshAll: Bool?
  let children: [InboxAction]?

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

  var isEnabled: Bool { enabled ?? true }
  var isBusy: Bool { busy ?? false }
  var isIncludedInRefreshAll: Bool { includeInRefreshAll ?? false }
  var hasChildren: Bool { children?.isEmpty == false }
}

struct InboxSourcePresentation: Codable, Equatable, Sendable {
  let name: String?
  let icon: String?
  let color: String?
  let order: Int?

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

struct InboxItem: Codable, Equatable, Identifiable, Sendable {
  let id: String
  let title: String
  let body: String?
  let format: InboxBodyFormat?
  let timestamp: TimeInterval?
  let category: String?
  let severity: InboxSeverity?
  let unread: Bool?
  let dismissible: Bool?
  let actions: [InboxAction]?
  let source: InboxSourcePresentation?
  let url: String?

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

  var resolvedFormat: InboxBodyFormat { format ?? .plain }
  var resolvedSeverity: InboxSeverity { severity ?? .info }
  var isInitiallyUnread: Bool { unread ?? true }
  var isDismissible: Bool { dismissible ?? true }
}

struct InboxSourceSnapshot: Codable, Equatable, Sendable {
  let source: String
  let items: [InboxItem]
}

struct InboxSourceConfiguration: Codable, Equatable, Sendable {
  let source: String
  let actions: [InboxAction]
  let order: Int?
  let presentation: InboxSourcePresentation?

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

  var refreshAllAction: InboxAction? {
    actions.first(where: \.isIncludedInRefreshAll)
  }
}

struct InboxPresentedItem: Identifiable, Equatable, Sendable {
  let source: String
  let item: InboxItem
  let isUnread: Bool

  var id: String { source + "\u{1f}" + item.id }
}
