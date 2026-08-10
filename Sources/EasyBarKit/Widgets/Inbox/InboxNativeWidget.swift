import Combine
import Foundation
import SwiftTOMLEdit

@MainActor
final class InboxNativeWidget: NativeWidget {
  let rootID = "builtin_inbox"
  let widgetStore: WidgetStore

  private var config: Config.InboxBuiltinConfig
  private let inboxStore: InboxStore
  private let configSnapshotStore: ConfigSnapshotStore
  private let configPersistence: ConfigPersistence
  private let eventObserver: EasyBarEventObserver
  private var cancellable: AnyCancellable?
  private var items: [InboxPresentedItem] = []

  init(
    config: Config.InboxBuiltinConfig,
    widgetStore: WidgetStore,
    inboxStore: InboxStore,
    configSnapshotStore: ConfigSnapshotStore,
    configPersistence: ConfigPersistence,
    eventHub: EventHub
  ) {
    self.config = config
    self.widgetStore = widgetStore
    self.inboxStore = inboxStore
    self.configSnapshotStore = configSnapshotStore
    self.configPersistence = configPersistence
    self.eventObserver = EasyBarEventObserver(eventHub: eventHub)
  }

  func start() {
    inboxStore.updateConfiguration(config)
    cancellable = inboxStore.$presentedItems.sink { [weak self] items in
      self?.items = items
      self?.publish(items: items)
    }
    eventObserver.start(
      eventNames: [WidgetEvent.contextMenuClicked.rawValue],
      widgetTargetIDs: [rootID]
    ) { [weak self] payload in
      guard payload.widgetID == self?.rootID, let actionID = payload.actionID else { return }
      self?.handleContextMenuAction(actionID)
    }
  }

  func stop() {
    cancellable?.cancel()
    cancellable = nil
    eventObserver.stop()
    clearNodes()
  }

  private func publish(items: [InboxPresentedItem]) {
    let unreadCount = items.lazy.filter(\.isUnread).count
    let hasUnread = unreadCount > 0
    let shouldShow = config.showWhenEmpty || !items.isEmpty
    let presentation = InboxAnchorPresentation.resolve(
      config: config,
      hasUnread: hasUnread
    )
    var node = BuiltinNativeNodeFactory.makeItemNode(
      rootID: rootID,
      placement: config.placement,
      style: config.style.chrome.widgetStyle(
        icon: presentation.icon,
        textColorHex: presentation.countColorHex
      ),
      text: config.showUnreadCount && hasUnread ? String(unreadCount) : ""
    )
    node.iconColor = presentation.iconColorHex
    node.visible = shouldShow
    node.contextMenu = InboxContextMenu.make(config: config)
    applyNodes([node])
  }

  private func handleContextMenuAction(_ actionID: String) {
    guard let action = InboxContextMenuAction(id: actionID) else { return }
    var updated = config
    let edit: TOMLEdit
    switch action {
    case .setGroup(let mode):
      updated.groupBy = mode
      edit = .init(path: ["builtins", "inbox", "content", "group_by"], value: .string(mode.rawValue))
    case .setSort(let mode):
      updated.sortBy = mode
      edit = .init(path: ["builtins", "inbox", "content", "sort_by"], value: .string(mode.rawValue))
    case .toggleDescending:
      updated.sortDescending.toggle()
      edit = .init(path: ["builtins", "inbox", "content", "sort_descending"], value: .bool(updated.sortDescending))
    case .toggleUnreadCount:
      updated.showUnreadCount.toggle()
      edit = .init(path: ["builtins", "inbox", "content", "show_unread_count"], value: .bool(updated.showUnreadCount))
    case .toggleInactiveStyle:
      updated.useInactiveStyleWhenRead.toggle()
      edit = .init(
        path: ["builtins", "inbox", "content", "use_inactive_style_when_read"],
        value: .bool(updated.useInactiveStyleWhenRead))
    case .toggleShowWhenEmpty:
      updated.showWhenEmpty.toggle()
      edit = .init(path: ["builtins", "inbox", "content", "show_when_empty"], value: .bool(updated.showWhenEmpty))
    case .toggleSourceActions:
      updated.showSourceActions.toggle()
      edit = .init(
        path: ["builtins", "inbox", "content", "show_source_actions"], value: .bool(updated.showSourceActions))
    }
    guard configPersistence.apply([edit]) else { return }
    config = updated
    inboxStore.updateConfiguration(updated)
    configSnapshotStore.applyInboxOverride(updated)
    publish(items: items)
  }
}

struct InboxAnchorPresentation: Equatable {
  let icon: String
  let iconColorHex: String?
  let countColorHex: String?

  static func resolve(
    config: Config.InboxBuiltinConfig,
    hasUnread: Bool
  ) -> InboxAnchorPresentation {
    let usesReadStyle = !hasUnread && config.useInactiveStyleWhenRead
    return InboxAnchorPresentation(
      icon: usesReadStyle ? config.style.readIcon : config.style.unreadIcon,
      iconColorHex: usesReadStyle
        ? config.style.readIconColorHex : config.style.unreadIconColorHex,
      countColorHex: usesReadStyle
        ? config.style.readIconColorHex : config.style.unreadCountColorHex
    )
  }
}
