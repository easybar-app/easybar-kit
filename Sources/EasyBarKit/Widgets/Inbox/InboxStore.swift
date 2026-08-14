import Combine
import EasyBarShared
import Foundation

@MainActor
final class InboxStore: ObservableObject {
  private static let compositeIDSeparator: Character = "\u{1f}"

  @Published private(set) var presentedItems: [InboxPresentedItem] = []
  @Published private(set) var sourceConfigurations: [InboxSourceConfiguration] = []

  private var sources: [String: [InboxItem]] = [:]
  private var controlSources: [String: [InboxItem]] = [:]
  private var sourceActions: [String: [InboxAction]] = [:]
  private var sourceActionOrders: [String: Int] = [:]
  private var sourcePresentations: [String: InboxSourcePresentation] = [:]
  private var readItemIDs = Set<String>()
  private var unreadItemIDs = Set<String>()
  private var dismissedItemIDs = Set<String>()
  private var configuration: Config.InboxBuiltinConfig
  private var persistence: InboxStatePersistence?
  private let logger: ProcessLogger

  init(
    configuration: Config.InboxBuiltinConfig = .default,
    stateURL: URL? = nil,
    logger: ProcessLogger = ProcessLogger(label: "easybar.inbox")
  ) {
    self.configuration = configuration
    self.logger = logger
    persistence = stateURL.map { InboxStatePersistence(fileURL: $0, logger: logger) }
    if let persistence {
      let state = persistence.load()
      readItemIDs = state.readItemIDs
      unreadItemIDs = state.unreadItemIDs
      dismissedItemIDs = state.dismissedItemIDs
    }
  }

  var unreadCount: Int {
    presentedItems.lazy.filter(\.isUnread).count
  }

  /// Returns every source action that participates in the native Refresh All command.
  var refreshAllTargets: [InboxSourceActionTarget] {
    sourceConfigurations.compactMap { configuration in
      guard let action = configuration.refreshAllAction else { return nil }
      return InboxSourceActionTarget(source: configuration.source, action: action)
    }
  }

  /// Returns Refresh All targets that can currently accept an action.
  var availableRefreshAllTargets: [InboxSourceActionTarget] {
    refreshAllTargets.filter { $0.action.isEnabled && !$0.action.isBusy }
  }

  func updateStateURL(_ stateURL: URL) {
    guard persistence?.fileURL.standardizedFileURL != stateURL.standardizedFileURL else { return }
    persistState()
    persistence = InboxStatePersistence(fileURL: stateURL, logger: logger)
    let state = persistence?.load() ?? .init()
    readItemIDs = state.readItemIDs
    unreadItemIDs = state.unreadItemIDs
    dismissedItemIDs = state.dismissedItemIDs
    rebuild()
  }

  func updateConfiguration(_ configuration: Config.InboxBuiltinConfig) {
    self.configuration = configuration
    rebuild()
  }

  func replace(source: String, items: [InboxItem]) {
    guard let source = normalizedSource(source) else { return }

    var uniqueItems: [String: InboxItem] = [:]
    var occupiedIDs = Set((controlSources[source] ?? []).map(\.id))
    for item in items where isValid(item) {
      let replacesExistingItem = uniqueItems[item.id] != nil || occupiedIDs.contains(item.id)
      let hasCapacity = occupiedIDs.count < configuration.maxItems
      if replacesExistingItem || hasCapacity {
        uniqueItems[item.id] = item
        occupiedIDs.insert(item.id)
      }
    }
    sources[source] = Array(uniqueItems.values)

    reconcileState(source: source)
    persistState()
    rebuild()
  }

  /// Adds or replaces one item without removing the source's other messages.
  @discardableResult
  func upsert(source: String, item: InboxItem) -> Bool {
    guard let source = normalizedSource(source), isValid(item) else { return false }
    let existingIDs = Set(
      (sources[source] ?? []).map(\.id) + (controlSources[source] ?? []).map(\.id))
    guard existingIDs.contains(item.id) || existingIDs.count < configuration.maxItems else {
      return false
    }
    var items = controlSources[source] ?? []
    items.removeAll { $0.id == item.id }
    items.append(item)
    controlSources[source] = items
    reconcileState(source: source)
    persistState()
    rebuild()
    return true
  }

  /// Returns visible items in their configured presentation order.
  func ipcItems(source: String? = nil, unreadOnly: Bool = false) -> [IPC.InboxItem] {
    let normalizedFilter: String?
    if let source {
      guard let normalized = normalizedSource(source) else { return [] }
      normalizedFilter = normalized
    } else {
      normalizedFilter = nil
    }
    return presentedItems.compactMap { presented in
      guard normalizedFilter == nil || presented.source == normalizedFilter else { return nil }
      guard !unreadOnly || presented.isUnread else { return nil }
      return IPC.InboxItem(
        source: presented.source,
        id: presented.item.id,
        title: presented.item.title,
        message: presented.item.body,
        severity: presented.item.resolvedSeverity,
        group: presented.item.category,
        url: presented.item.url,
        timestamp: presented.item.timestamp ?? 0,
        unread: presented.isUnread
      )
    }
  }

  /// Changes read state for one item or all matching visible items.
  func setRead(_ read: Bool, source: String?, id: String?) -> Bool {
    let matches = matchingItems(source: source, id: id)
    for item in matches {
      if read { markRead(item) } else { markUnread(item) }
    }
    return !matches.isEmpty
  }

  /// Dismisses one item or all matching visible items.
  func dismiss(source: String?, id: String?) -> Bool {
    let matches = matchingItems(source: source, id: id).filter(\.item.isDismissible)
    for item in matches { dismiss(item) }
    return !matches.isEmpty
  }

  /// Removes one item and its local state from both publication channels.
  func remove(source: String, id: String) -> Bool {
    guard let source = normalizedSource(source), !id.isEmpty else { return false }
    let luaCount = sources[source]?.count ?? 0
    let controlCount = controlSources[source]?.count ?? 0
    sources[source]?.removeAll { $0.id == id }
    controlSources[source]?.removeAll { $0.id == id }
    if sources[source]?.isEmpty == true { sources.removeValue(forKey: source) }
    if controlSources[source]?.isEmpty == true { controlSources.removeValue(forKey: source) }
    let removed =
      luaCount != (sources[source]?.count ?? 0)
      || controlCount != (controlSources[source]?.count ?? 0)
    guard removed else { return false }

    let compositeID = compositeID(source: source, itemID: id)
    readItemIDs.remove(compositeID)
    unreadItemIDs.remove(compositeID)
    dismissedItemIDs.remove(compositeID)
    persistState()
    rebuild()
    return true
  }

  func clear(source: String) {
    guard let source = normalizedSource(source) else { return }
    sources.removeValue(forKey: source)
    reconcileState(source: source)
    persistState()
    rebuild()
  }

  /// Clears every Lua- and control-owned item for a source.
  func clearFromControl(source: String) {
    guard let source = normalizedSource(source) else { return }
    sources.removeValue(forKey: source)
    controlSources.removeValue(forKey: source)
    let prefix = source + String(Self.compositeIDSeparator)
    readItemIDs = readItemIDs.filter { !$0.hasPrefix(prefix) }
    unreadItemIDs = unreadItemIDs.filter { !$0.hasPrefix(prefix) }
    dismissedItemIDs = dismissedItemIDs.filter { !$0.hasPrefix(prefix) }
    persistState()
    rebuild()
  }

  func clearAll() {
    sources.removeAll()
    controlSources.removeAll()
    sourceActions.removeAll()
    sourceActionOrders.removeAll()
    sourcePresentations.removeAll()
    readItemIDs.removeAll()
    unreadItemIDs.removeAll()
    dismissedItemIDs.removeAll()
    persistState()
    rebuild()
    rebuildSourceConfigurations()
  }

  func clearPublishedItems() {
    sources.removeAll()
    sourceActions.removeAll()
    sourceActionOrders.removeAll()
    sourcePresentations.removeAll()
    rebuild()
    rebuildSourceConfigurations()
  }

  func configure(
    source: String,
    actions: [InboxAction],
    order: Int? = nil,
    presentation: InboxSourcePresentation? = nil
  ) {
    guard let source = normalizedSource(source) else { return }
    var actionIDs = Set<String>()
    var hasRefreshAllAction = false
    var remainingActionCapacity = 32
    let validActions = validSourceActions(
      actions,
      depth: 1,
      actionIDs: &actionIDs,
      hasRefreshAllAction: &hasRefreshAllAction,
      remainingCapacity: &remainingActionCapacity
    )
    if validActions.isEmpty {
      sourceActions.removeValue(forKey: source)
      sourceActionOrders.removeValue(forKey: source)
      sourcePresentations.removeValue(forKey: source)
    } else {
      sourceActions[source] = validActions
      if let order {
        sourceActionOrders[source] = order
      } else {
        sourceActionOrders.removeValue(forKey: source)
      }
      if let presentation {
        sourcePresentations[source] = presentation
      } else {
        sourcePresentations.removeValue(forKey: source)
      }
    }
    rebuildSourceConfigurations()
  }

  func markRead(_ presentedItem: InboxPresentedItem) {
    readItemIDs.insert(presentedItem.id)
    unreadItemIDs.remove(presentedItem.id)
    persistState()
    rebuild()
  }

  func markUnread(_ presentedItem: InboxPresentedItem) {
    readItemIDs.remove(presentedItem.id)
    unreadItemIDs.insert(presentedItem.id)
    dismissedItemIDs.remove(presentedItem.id)
    persistState()
    rebuild()
  }

  func toggleRead(_ presentedItem: InboxPresentedItem) {
    if presentedItem.isUnread {
      markRead(presentedItem)
    } else {
      markUnread(presentedItem)
    }
  }

  func markAllRead() {
    for item in presentedItems where item.isUnread {
      readItemIDs.insert(item.id)
      unreadItemIDs.remove(item.id)
    }
    persistState()
    rebuild()
  }

  func dismiss(_ presentedItem: InboxPresentedItem) {
    guard presentedItem.item.isDismissible else { return }
    dismissedItemIDs.insert(presentedItem.id)
    readItemIDs.remove(presentedItem.id)
    unreadItemIDs.remove(presentedItem.id)
    persistState()
    rebuild()
  }

  func dismissAll() {
    for item in presentedItems where item.item.isDismissible {
      dismissedItemIDs.insert(item.id)
      readItemIDs.remove(item.id)
      unreadItemIDs.remove(item.id)
    }
    persistState()
    rebuild()
  }

  func groups() -> [(
    title: String?, sourcePresentation: InboxSourcePresentation?, items: [InboxPresentedItem]
  )] {
    guard configuration.groupBy != .none else {
      return [(nil, nil, presentedItems)]
    }

    var order: [String] = []
    var grouped: [String: [InboxPresentedItem]] = [:]
    for item in presentedItems {
      let title = groupTitle(for: item)
      if grouped[title] == nil { order.append(title) }
      grouped[title, default: []].append(item)
    }
    let groups = order.map { title in
      let items = grouped[title] ?? []
      let presentation = configuration.groupBy == .source ? items.first?.item.source : nil
      return (title, presentation, items)
    }
    guard configuration.groupBy == .source else { return groups }
    return groups.enumerated().sorted { left, right in
      let leftOrder = left.element.1?.order
      let rightOrder = right.element.1?.order
      switch (leftOrder, rightOrder) {
      case (let leftOrder?, let rightOrder?) where leftOrder != rightOrder:
        return leftOrder < rightOrder
      case (_?, nil):
        return true
      case (nil, _?):
        return false
      case (_?, _?):
        return left.element.0.localizedCaseInsensitiveCompare(right.element.0) == .orderedAscending
      case (nil, nil):
        return left.offset < right.offset
      }
    }.map { $0.element }
  }

  private func rebuild() {
    var mergedSources = sources
    for (source, controlItems) in controlSources {
      var mergedItems = Dictionary(
        uniqueKeysWithValues: (mergedSources[source] ?? []).map { ($0.id, $0) })
      for item in controlItems { mergedItems[item.id] = item }
      mergedSources[source] = Array(mergedItems.values)
    }

    let flattened: [InboxPresentedItem] = mergedSources.flatMap { source, items in
      items.compactMap { item in
        let id = compositeID(source: source, itemID: item.id)
        guard !dismissedItemIDs.contains(id) else { return nil }
        return InboxPresentedItem(
          source: source,
          item: item,
          isUnread: unreadItemIDs.contains(id)
            || (item.isInitiallyUnread
              && !readItemIDs.contains(id))
        )
      }
    }

    presentedItems = flattened.sorted(by: compare)
  }

  private func compare(_ left: InboxPresentedItem, _ right: InboxPresentedItem) -> Bool {
    let result: ComparisonResult
    switch configuration.sortBy {
    case .timestamp:
      result = compareValues(left.item.timestamp ?? 0, right.item.timestamp ?? 0)
    case .source:
      result = left.source.localizedCaseInsensitiveCompare(right.source)
    case .severity:
      result = compareValues(left.item.resolvedSeverity.rank, right.item.resolvedSeverity.rank)
    case .title:
      result = left.item.title.localizedCaseInsensitiveCompare(right.item.title)
    }
    if result == .orderedSame { return left.id < right.id }
    return configuration.sortDescending ? result == .orderedDescending : result == .orderedAscending
  }

  private func compareValues<T: Comparable>(_ left: T, _ right: T) -> ComparisonResult {
    if left < right { return .orderedAscending }
    if left > right { return .orderedDescending }
    return .orderedSame
  }

  private func groupTitle(for item: InboxPresentedItem) -> String {
    switch configuration.groupBy {
    case .source:
      return nonempty(item.item.source?.name) ?? item.source
    case .category:
      return nonempty(item.item.category) ?? "Other"
    case .severity:
      return item.item.resolvedSeverity.rawValue.capitalized
    case .date:
      guard let timestamp = item.item.timestamp else { return "No date" }
      let date = Date(timeIntervalSince1970: timestamp)
      if Calendar.current.isDateInToday(date) { return "Today" }
      if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
      return date.formatted(date: .abbreviated, time: .omitted)
    case .none:
      return ""
    }
  }

  private func nonempty(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private func matchingItems(source: String?, id: String?) -> [InboxPresentedItem] {
    let normalizedFilter: String?
    if let source {
      guard let normalized = normalizedSource(source) else { return [] }
      normalizedFilter = normalized
    } else {
      normalizedFilter = nil
    }
    return presentedItems.filter { item in
      (normalizedFilter == nil || item.source == normalizedFilter)
        && (id == nil || item.item.id == id)
    }
  }

  private func normalizedSource(_ source: String) -> String? {
    let source = source.trimmingCharacters(in: .whitespacesAndNewlines)
    return source.isEmpty || source.utf8.count > 512
      || source.contains(Self.compositeIDSeparator) ? nil : source
  }

  private func compositeID(source: String, itemID: String) -> String {
    source + String(Self.compositeIDSeparator) + itemID
  }

  private func reconcileState(source: String) {
    let prefix = source + String(Self.compositeIDSeparator)
    let items = (sources[source] ?? []) + (controlSources[source] ?? [])
    let liveIDs = Set(items.map { compositeID(source: source, itemID: $0.id) })
    readItemIDs = readItemIDs.filter { !$0.hasPrefix(prefix) || liveIDs.contains($0) }
    unreadItemIDs = unreadItemIDs.filter { !$0.hasPrefix(prefix) || liveIDs.contains($0) }
    dismissedItemIDs = dismissedItemIDs.filter { !$0.hasPrefix(prefix) || liveIDs.contains($0) }
  }

  private func persistState() {
    persistence?.save(
      InboxPersistedState(
        readItemIDs: readItemIDs,
        unreadItemIDs: unreadItemIDs,
        dismissedItemIDs: dismissedItemIDs
      ))
  }

  private func rebuildSourceConfigurations() {
    sourceConfigurations = sourceActions.keys.map {
      InboxSourceConfiguration(
        source: $0,
        actions: sourceActions[$0] ?? [],
        order: sourceActionOrders[$0],
        presentation: sourcePresentations[$0]
      )
    }.sorted { left, right in
      switch (left.order, right.order) {
      case (let leftOrder?, let rightOrder?) where leftOrder != rightOrder:
        return leftOrder < rightOrder
      case (_?, nil):
        return true
      case (nil, _?):
        return false
      default:
        return left.source.localizedCaseInsensitiveCompare(right.source) == .orderedAscending
      }
    }
  }

  private func isValidAction(_ action: InboxAction) -> Bool {
    !action.id.isEmpty && action.id.utf8.count <= 512
      && !action.title.isEmpty && action.title.utf8.count <= 1_024
  }

  private func validSourceActions(
    _ actions: [InboxAction],
    depth: Int,
    actionIDs: inout Set<String>,
    hasRefreshAllAction: inout Bool,
    remainingCapacity: inout Int
  ) -> [InboxAction] {
    guard depth <= 3, remainingCapacity > 0 else { return [] }
    var validActions: [InboxAction] = []

    for action in actions {
      let previousActionIDs = actionIDs
      let previousRefreshAllState = hasRefreshAllAction
      let previousCapacity = remainingCapacity
      guard remainingCapacity > 0, isValidAction(action), actionIDs.insert(action.id).inserted
      else {
        continue
      }

      let children = action.children ?? []
      if !children.isEmpty {
        guard depth < 3, !action.isBusy, !action.isIncludedInRefreshAll else {
          actionIDs = previousActionIDs
          continue
        }
        remainingCapacity -= 1
        let validChildren = validSourceActions(
          children,
          depth: depth + 1,
          actionIDs: &actionIDs,
          hasRefreshAllAction: &hasRefreshAllAction,
          remainingCapacity: &remainingCapacity
        )
        guard !validChildren.isEmpty else {
          actionIDs = previousActionIDs
          hasRefreshAllAction = previousRefreshAllState
          remainingCapacity = previousCapacity
          continue
        }
        validActions.append(
          InboxAction(
            id: action.id,
            title: action.title,
            enabled: action.enabled,
            children: validChildren
          )
        )
      } else {
        if action.children != nil {
          actionIDs = previousActionIDs
          continue
        }
        if action.isIncludedInRefreshAll {
          guard depth == 1, !hasRefreshAllAction else {
            actionIDs = previousActionIDs
            continue
          }
          hasRefreshAllAction = true
        }
        remainingCapacity -= 1
        validActions.append(action)
      }
    }

    return validActions
  }

  private func isValid(_ item: InboxItem) -> Bool {
    let id = item.id.trimmingCharacters(in: .whitespacesAndNewlines)
    let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !id.isEmpty, id.utf8.count <= 512, !id.contains(Self.compositeIDSeparator),
      !title.isEmpty, title.utf8.count <= 4_096
    else {
      return false
    }
    guard (item.body?.utf8.count ?? 0) <= 64 * 1_024 else { return false }
    guard (item.url?.utf8.count ?? 0) <= 8 * 1_024 else { return false }
    let actions = item.actions ?? []
    return actions.count <= 16
      && actions.allSatisfy(isValidAction)
      && actions.allSatisfy { !$0.hasChildren && $0.children == nil }
      && actions.allSatisfy { !$0.isIncludedInRefreshAll }
      && Set(actions.map(\.id)).count == actions.count
  }
}
