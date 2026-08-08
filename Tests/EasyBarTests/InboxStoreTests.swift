import EasyBarShared
import XCTest

@testable import EasyBarApp

@MainActor
final class InboxStoreTests: XCTestCase {
  func testControlSocketItemsCanBeUpsertedReadAndDismissed() {
    let store = InboxStore()
    let first = InboxItem(
      id: "nightly",
      title: "Backup failed",
      timestamp: 100,
      category: "backup:minio",
      severity: .error,
      url: "https://grafana.example.com/backup-logs"
    )

    XCTAssertTrue(store.upsert(source: "backup", item: first))
    XCTAssertEqual(store.ipcItems().map(\.title), ["Backup failed"])
    XCTAssertTrue(store.setRead(true, source: "backup", id: "nightly"))
    XCTAssertFalse(store.ipcItems().first?.unread ?? true)

    let replacement = InboxItem(id: "nightly", title: "Backup recovered", timestamp: 101)
    XCTAssertTrue(store.upsert(source: "backup", item: replacement))
    XCTAssertEqual(store.ipcItems().map(\.title), ["Backup recovered"])
    XCTAssertFalse(store.ipcItems().first?.unread ?? true)

    XCTAssertTrue(store.dismiss(source: "backup", id: "nightly"))
    XCTAssertTrue(store.ipcItems().isEmpty)
  }

  func testControlSocketItemsSurviveLuaRefreshAndRuntimeClear() {
    let store = InboxStore()
    XCTAssertTrue(
      store.upsert(
        source: "backup",
        item: InboxItem(id: "cli", title: "CLI alert", timestamp: 2)
      )
    )

    store.replace(
      source: "backup",
      items: [InboxItem(id: "lua", title: "Lua alert", timestamp: 1)]
    )
    XCTAssertEqual(Set(store.ipcItems().map(\.id)), ["cli", "lua"])

    store.clearPublishedItems()
    XCTAssertEqual(store.ipcItems().map(\.id), ["cli"])
  }

  func testRemoveDeletesOneItemAcrossPublicationChannels() {
    let store = InboxStore()
    store.replace(
      source: "backup",
      items: [
        InboxItem(id: "shared", title: "Lua copy"),
        InboxItem(id: "lua-only", title: "Lua only"),
      ]
    )
    XCTAssertTrue(
      store.upsert(source: "backup", item: InboxItem(id: "shared", title: "CLI copy"))
    )

    XCTAssertTrue(store.remove(source: "backup", id: "shared"))
    XCTAssertEqual(store.ipcItems().map(\.id), ["lua-only"])
    XCTAssertFalse(store.remove(source: "backup", id: "missing"))
  }

  func testReplacementTracksUnreadStateAndRemovesStaleItems() {
    let store = InboxStore()
    store.replace(source: "GitLab", items: [item("one", timestamp: 1), item("two", timestamp: 2)])

    XCTAssertEqual(store.presentedItems.map(\.item.id), ["two", "one"])
    XCTAssertEqual(store.unreadCount, 2)

    store.markRead(store.presentedItems[0])
    XCTAssertEqual(store.unreadCount, 1)

    store.replace(source: "GitLab", items: [item("two", timestamp: 3)])
    XCTAssertEqual(store.presentedItems.map(\.item.id), ["two"])
    XCTAssertEqual(store.unreadCount, 0)
  }

  func testReplacementLimitCountsUniqueItemIDs() {
    var config = Config.InboxBuiltinConfig.default
    config.maxItems = 2
    let store = InboxStore(configuration: config)

    store.replace(
      source: "GitHub",
      items: [
        item("one", title: "Older"),
        item("one", title: "Newer"),
        item("two", title: "Second"),
        item("three", title: "Over limit"),
      ]
    )

    XCTAssertEqual(Set(store.presentedItems.map(\.item.id)), ["one", "two"])
    XCTAssertEqual(store.presentedItems.first { $0.item.id == "one" }?.item.title, "Newer")
  }

  func testGroupingUsesConfiguredCategoryAndFallback() {
    var config = Config.InboxBuiltinConfig.default
    config.groupBy = .category
    let store = InboxStore(configuration: config)
    store.replace(
      source: "GitLab",
      items: [item("one", category: "Reviews"), item("two", category: nil)]
    )

    XCTAssertEqual(store.groups().map(\.title), ["Reviews", "Other"])
  }

  func testSourceGroupingUsesPresentationWithoutChangingPublisherIdentity() {
    let store = InboxStore()
    let github = InboxSourcePresentation(name: "GitHub", icon: "GH", color: "#ffffff")
    let gitlab = InboxSourcePresentation(name: "GitLab", icon: "GL", color: "#fc6d26")
    store.replace(
      source: "Inbox demo",
      items: [
        item("github-one", sourcePresentation: github),
        item("github-two", sourcePresentation: github),
        item("gitlab-one", sourcePresentation: gitlab),
      ]
    )

    let groups = store.groups()
    XCTAssertEqual(groups.map(\.title), ["GitHub", "GitLab"])
    XCTAssertEqual(groups.map(\.sourcePresentation), [github, gitlab])
    XCTAssertEqual(store.presentedItems.map(\.source), ["Inbox demo", "Inbox demo", "Inbox demo"])
  }

  func testSourceGroupingUsesExplicitOrderBeforeUnorderedSources() {
    let store = InboxStore()
    store.replace(
      source: "GitHub",
      items: [
        item(
          "github",
          timestamp: 30,
          sourcePresentation: InboxSourcePresentation(name: "GitHub", order: 20)
        )
      ]
    )
    store.replace(
      source: "GitLab",
      items: [
        item(
          "gitlab",
          timestamp: 20,
          sourcePresentation: InboxSourcePresentation(name: "GitLab", order: 10)
        )
      ]
    )
    store.replace(source: "Other", items: [item("other", timestamp: 40)])

    XCTAssertEqual(store.groups().map(\.title), ["GitLab", "GitHub", "Other"])
  }

  func testClearAllRemovesMessagesAndReadState() {
    let store = InboxStore()
    store.replace(source: "GitHub", items: [item("one")])
    store.markAllRead()
    store.clearAll()
    store.replace(source: "GitHub", items: [item("one")])

    XCTAssertEqual(store.unreadCount, 1)
  }

  func testReadStateCanBeToggledAndPersistsAcrossReplacement() {
    let store = InboxStore()
    store.replace(source: "GitHub", items: [item("one")])
    let original = store.presentedItems[0]

    store.toggleRead(original)
    XCTAssertEqual(store.unreadCount, 0)

    store.toggleRead(store.presentedItems[0])
    XCTAssertEqual(store.unreadCount, 1)

    store.replace(source: "GitHub", items: [item("one")])
    XCTAssertEqual(store.unreadCount, 1)
  }

  func testInitiallyReadItemCanBeMarkedUnread() {
    let store = InboxStore()
    var readItem = item("one")
    readItem = InboxItem(
      id: readItem.id,
      title: readItem.title,
      body: readItem.body,
      format: readItem.format,
      timestamp: readItem.timestamp,
      category: readItem.category,
      severity: readItem.severity,
      unread: false,
      dismissible: readItem.dismissible,
      actions: readItem.actions,
      source: readItem.source
    )
    store.replace(source: "GitHub", items: [readItem])

    store.markUnread(store.presentedItems[0])

    XCTAssertEqual(store.unreadCount, 1)
  }

  func testDismissSuppressesItemUntilPublisherRemovesIt() {
    let store = InboxStore()
    store.replace(source: "GitHub", items: [item("one")])
    store.dismiss(store.presentedItems[0])
    XCTAssertTrue(store.presentedItems.isEmpty)

    store.replace(source: "GitHub", items: [item("one")])
    XCTAssertTrue(store.presentedItems.isEmpty)

    store.replace(source: "GitHub", items: [])
    store.replace(source: "GitHub", items: [item("one")])
    XCTAssertEqual(store.presentedItems.map(\.item.id), ["one"])
  }

  func testDismissAllKeepsNonDismissibleControls() {
    let store = InboxStore()
    store.replace(
      source: "Homebrew",
      items: [item("package"), item("controls", dismissible: false)]
    )

    store.dismissAll()

    XCTAssertEqual(store.presentedItems.map(\.item.id), ["controls"])
  }

  func testLocalStatePersistsWithoutMessageContentAndReconcilesPerSource() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let stateURL = directory.appendingPathComponent("inbox-state.json")
    defer { try? FileManager.default.removeItem(at: directory) }

    let first = InboxStore(stateURL: stateURL)
    first.replace(source: "GitHub", items: [item("gh-1", title: "github-secret-title")])
    first.markRead(first.presentedItems[0])
    first.replace(source: "GitLab", items: [item("gl-1", title: "gitlab-secret-title")])
    first.dismiss(first.presentedItems.first { $0.source == "GitLab" }!)

    let persistedText = try String(contentsOf: stateURL, encoding: .utf8)
    XCTAssertFalse(persistedText.contains("secret-title"))

    let restored = InboxStore(stateURL: stateURL)
    restored.replace(source: "GitHub", items: [item("gh-1", title: "github-secret-title")])
    XCTAssertEqual(restored.unreadCount, 0)
    restored.replace(source: "GitLab", items: [item("gl-1", title: "gitlab-secret-title")])
    XCTAssertEqual(restored.presentedItems.map(\.source), ["GitHub"])
  }

  func testInvalidItemsAreDropped() {
    let store = InboxStore()
    store.replace(source: "GitLab", items: [item(""), item("valid")])

    XCTAssertEqual(store.presentedItems.map(\.item.id), ["valid"])
  }

  func testCompositeIDSeparatorIsRejectedInSourcesAndItemIDs() {
    let store = InboxStore()
    store.replace(source: "GitHub\u{1f}shared", items: [item("one")])
    store.replace(source: "GitHub", items: [item("shared\u{1f}one"), item("valid")])

    XCTAssertEqual(store.presentedItems.map(\.item.id), ["valid"])
    XCTAssertEqual(store.presentedItems.map(\.source), ["GitHub"])
  }

  func testSourceActionsRemainConfiguredWhenMessagesAreCleared() {
    let store = InboxStore()
    let presentation = InboxSourcePresentation(
      name: "GitLab",
      icon: "GL",
      color: "#FC6D26"
    )
    store.configure(
      source: "GitLab",
      actions: [
        InboxAction(id: "sync", title: "Refresh", includeInRefreshAll: true)
      ],
      presentation: presentation
    )

    XCTAssertEqual(
      store.sourceConfigurations,
      [
        InboxSourceConfiguration(
          source: "GitLab",
          actions: [
            InboxAction(id: "sync", title: "Refresh", includeInRefreshAll: true)
          ],
          presentation: presentation
        )
      ]
    )

    store.clear(source: "GitLab")
    XCTAssertEqual(store.sourceConfigurations.first?.source, "GitLab")
    XCTAssertEqual(store.sourceConfigurations.first?.presentation, presentation)

    store.configure(source: "GitLab", actions: [])
    XCTAssertTrue(store.sourceConfigurations.isEmpty)
  }

  func testSourceActionsUseContextOrderBeforeUnorderedSources() {
    let store = InboxStore()
    let refresh = [InboxAction(id: "refresh", title: "Refresh")]
    store.configure(source: "Other", actions: refresh)
    store.configure(source: "GitHub", actions: refresh, order: 20)
    store.configure(source: "GitLab", actions: refresh, order: 10)

    XCTAssertEqual(store.sourceConfigurations.map(\.source), ["GitLab", "GitHub", "Other"])
    XCTAssertEqual(store.sourceConfigurations.map(\.order), [10, 20, nil])
  }

  func testRefreshAllTargetsContainOnlyOptedInSourceActions() {
    let store = InboxStore()
    store.configure(
      source: "GitHub",
      actions: [
        InboxAction(id: "sync", title: "Sync now", includeInRefreshAll: true),
        InboxAction(id: "open", title: "Open"),
      ]
    )
    store.configure(
      source: "GitLab",
      actions: [
        InboxAction(
          id: "reload",
          title: "Refreshing…",
          enabled: false,
          busy: true,
          includeInRefreshAll: true
        )
      ]
    )
    store.configure(
      source: "Other",
      actions: [InboxAction(id: "refresh", title: "Refresh")]
    )

    XCTAssertEqual(store.refreshAllTargets.map(\.source), ["GitHub", "GitLab"])
    XCTAssertEqual(store.refreshAllTargets.map(\.action.id), ["sync", "reload"])
    XCTAssertEqual(store.availableRefreshAllTargets.map(\.source), ["GitHub"])
  }

  func testOnlyOneSourceActionCanJoinRefreshAll() {
    let store = InboxStore()
    store.configure(
      source: "GitHub",
      actions: [
        InboxAction(id: "sync", title: "Sync", includeInRefreshAll: true),
        InboxAction(id: "reload", title: "Reload", includeInRefreshAll: true),
        InboxAction(id: "open", title: "Open"),
      ]
    )

    XCTAssertEqual(store.sourceConfigurations.first?.actions.map(\.id), ["sync", "open"])
    XCTAssertEqual(store.refreshAllTargets.map(\.action.id), ["sync"])
  }

  func testItemActionsCannotJoinRefreshAll() {
    let store = InboxStore()
    let invalidItem = InboxItem(
      id: "one",
      title: "One",
      actions: [InboxAction(id: "sync", title: "Sync", includeInRefreshAll: true)]
    )

    store.replace(source: "GitHub", items: [invalidItem])

    XCTAssertTrue(store.presentedItems.isEmpty)
  }

  func testSourceIsNormalizedConsistently() {
    let store = InboxStore()
    store.replace(source: "  GitLab\n", items: [item("one")])
    store.configure(
      source: "\tGitLab ",
      actions: [InboxAction(id: "refresh", title: "Refresh")]
    )

    XCTAssertEqual(store.presentedItems.map(\.source), ["GitLab"])
    XCTAssertEqual(store.sourceConfigurations.map(\.source), ["GitLab"])

    store.clear(source: " GitLab ")

    XCTAssertTrue(store.presentedItems.isEmpty)
  }

  func testInvalidSourceContextActionsAreDropped() {
    let store = InboxStore()
    store.configure(
      source: "GitLab",
      actions: [InboxAction(id: "", title: "Refresh")]
    )

    XCTAssertTrue(store.sourceConfigurations.isEmpty)
  }

  func testDuplicateActionIDsAreRejectedOrDeduplicated() {
    let duplicateActions = [
      InboxAction(id: "open", title: "Open first"),
      InboxAction(id: "open", title: "Open second"),
    ]
    let store = InboxStore()
    var message = item("one")
    message = InboxItem(
      id: message.id,
      title: message.title,
      body: message.body,
      format: message.format,
      timestamp: message.timestamp,
      category: message.category,
      severity: message.severity,
      unread: message.unread,
      dismissible: message.dismissible,
      actions: duplicateActions,
      source: message.source
    )

    store.replace(source: "GitLab", items: [message])
    store.configure(source: "GitLab", actions: duplicateActions)

    XCTAssertTrue(store.presentedItems.isEmpty)
    XCTAssertEqual(
      store.sourceConfigurations.first?.actions,
      [InboxAction(id: "open", title: "Open first")]
    )
  }

  func testPersistedStateIsFormattedAndDeterministic() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let stateURL = directory.appendingPathComponent("inbox-state.json")
    defer { try? FileManager.default.removeItem(at: directory) }
    let persistence = InboxStatePersistence(
      fileURL: stateURL,
      logger: ProcessLogger(label: "inbox.persistence.test", minimumLevel: .error)
    )
    let state = InboxPersistedState(
      readItemIDs: ["GitHub\u{1f}z/item", "GitHub\u{1f}a/item"],
      unreadItemIDs: ["GitLab\u{1f}one"],
      dismissedItemIDs: []
    )

    persistence.save(state)

    let text = try String(contentsOf: stateURL, encoding: .utf8)
    XCTAssertTrue(text.hasSuffix("\n"))
    XCTAssertTrue(text.contains("\n  \"dismissedItemIDs\" : ["))
    XCTAssertTrue(text.contains("GitHub\\u001fa/item"))
    XCTAssertTrue(text.contains("GitHub\\u001fz/item"))
    XCTAssertFalse(text.contains("z\\/item"))
    XCTAssertLessThan(
      try XCTUnwrap(text.range(of: "GitHub\\u001fa/item")?.lowerBound),
      try XCTUnwrap(text.range(of: "GitHub\\u001fz/item")?.lowerBound)
    )
    XCTAssertEqual(persistence.load(), state)
  }

  private func item(
    _ id: String,
    title: String? = nil,
    timestamp: TimeInterval = 0,
    category: String? = nil,
    dismissible: Bool? = nil,
    sourcePresentation: InboxSourcePresentation? = nil
  ) -> InboxItem {
    InboxItem(
      id: id,
      title: title ?? id,
      body: nil,
      format: nil,
      timestamp: timestamp,
      category: category,
      severity: nil,
      unread: nil,
      dismissible: dismissible,
      actions: nil,
      source: sourcePresentation
    )
  }
}
