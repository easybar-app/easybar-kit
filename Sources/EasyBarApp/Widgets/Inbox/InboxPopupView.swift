import AppKit
import SwiftUI

struct InboxPopupView: View {
  @ObservedObject var store: InboxStore
  let eventHub: EventHub
  let popupPanel: WidgetPopupPanelController
  let onSourceActionsMenuClosed: () -> Void
  @EnvironmentObject private var configStore: ConfigSnapshotStore
  @State private var holdsSourceActionOpen = false
  @State private var observedSourceActivity = false
  @State private var sourceActionHoldTask: Task<Void, Never>?

  var body: some View {
    let config = configStore.snapshot.builtins.inbox
    let activities = sourceActivityRows
    let busySourceActions = Dictionary(grouping: activities, by: \.source)
      .mapValues { $0.map(\.action) }
    let headerActionColor = color(config.popupMutedColorHex)
    let tooltipTextColor = color(config.popupTitleColorHex)
    let tooltipBackgroundColor = color(config.popupItemBackgroundColorHex)
    let tooltipBorderColor = color(config.popupBorderColorHex)

    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("Inbox").font(.headline).foregroundStyle(color(config.popupTitleColorHex))
        Spacer()
        if config.showRefreshAll, !store.refreshAllTargets.isEmpty {
          InboxHeaderActionButton(
            tooltip: config.refreshAllTooltip,
            systemImage: config.refreshAllIcon,
            isEnabled: !store.availableRefreshAllTargets.isEmpty,
            tintColor: headerActionColor,
            tooltipTextColor: tooltipTextColor,
            tooltipBackgroundColor: tooltipBackgroundColor,
            tooltipBorderColor: tooltipBorderColor,
            action: refreshAllSources
          )
        }
        if config.showMarkAllRead, store.unreadCount > 0 {
          InboxHeaderActionButton(
            tooltip: config.markAllReadTooltip,
            systemImage: config.markAllReadIcon,
            isEnabled: true,
            tintColor: headerActionColor,
            tooltipTextColor: tooltipTextColor,
            tooltipBackgroundColor: tooltipBackgroundColor,
            tooltipBorderColor: tooltipBorderColor,
            action: store.markAllRead
          )
        }
        if config.showDismissAll, !store.presentedItems.isEmpty {
          InboxHeaderActionButton(
            tooltip: config.dismissAllTooltip,
            systemImage: config.dismissAllIcon,
            isEnabled: true,
            tintColor: headerActionColor,
            tooltipTextColor: tooltipTextColor,
            tooltipBackgroundColor: tooltipBackgroundColor,
            tooltipBorderColor: tooltipBorderColor,
            action: store.dismissAll
          )
        }
        if config.showSourceActions, !store.sourceConfigurations.isEmpty {
          InboxSourceActionsMenuButton(
            configurations: store.sourceConfigurations,
            tintColor: NSColor(color(config.popupMutedColorHex)),
            popupPanel: popupPanel,
            onAction: { source, actionID in
              beginSourceActionHold(hasActivity: !activities.isEmpty)
              emitAction(
                .inboxContextAction,
                actionID: actionID,
                source: source,
                targetWidgetID: "builtin_inbox"
              )
            },
            onMenuClosed: handleSourceActionsMenuClosed
          )
          .frame(width: 16, height: 16)
          .fixedSize()
          .help("Inbox actions")
        }
      }
      .zIndex(1)

      if !activities.isEmpty {
        VStack(alignment: .leading, spacing: 5) {
          ForEach(activities) { activity in
            sourceActivityView(activity, config: config)
          }
        }
      }

      if store.presentedItems.isEmpty {
        Text("No messages")
          .foregroundStyle(color(config.popupMutedColorHex))
          .padding(.vertical, 8)
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(Array(store.groups().enumerated()), id: \.offset) { _, group in
              if let title = group.title {
                sourceGroupHeader(
                  title: title,
                  presentation: group.sourcePresentation,
                  config: config
                )
              }
              ForEach(group.items) { item in
                itemView(
                  item,
                  busySourceActions: busySourceActions[item.source] ?? [],
                  config: config
                )
              }
            }
          }
          .id(config.groupBy)
        }
        .frame(maxHeight: CGFloat(config.popupMaxHeight))
      }
    }
    .frame(width: CGFloat(config.popupWidth), alignment: .leading)
    .padding(12)
    .background(color(config.popupBackgroundColorHex))
    .overlay {
      RoundedRectangle(cornerRadius: 10)
        .stroke(
          color(config.popupBorderColorHex),
          lineWidth: 1
        )
    }
    .clipShape(RoundedRectangle(cornerRadius: 10))
    .onChange(of: store.presentedItems, initial: false) { _, _ in
      popupPanel.scheduleContentLayoutRefresh()
    }
    .onChange(of: store.sourceConfigurations, initial: false) { _, _ in
      popupPanel.scheduleContentLayoutRefresh()
    }
    .onChange(of: activities.map(\.id), initial: false) { _, activityIDs in
      handleSourceActivityChange(hasActivity: !activityIDs.isEmpty)
    }
    .onDisappear {
      releaseSourceActionHold()
    }
  }

  /// Requests every available source action that opted into Refresh All.
  private func refreshAllSources() {
    let targets = store.availableRefreshAllTargets
    guard !targets.isEmpty else { return }

    beginSourceActionHold(hasActivity: !sourceActivityRows.isEmpty)
    for target in targets {
      emitAction(
        .inboxContextAction,
        actionID: target.action.id,
        source: target.source,
        targetWidgetID: "builtin_inbox"
      )
    }
  }

  private func beginSourceActionHold(hasActivity: Bool) {
    guard !holdsSourceActionOpen else { return }

    holdsSourceActionOpen = true
    observedSourceActivity = hasActivity
    popupPanel.beginTransientInteraction()

    guard !hasActivity else { return }
    sourceActionHoldTask?.cancel()
    sourceActionHoldTask = Task { @MainActor in
      do {
        try await Task.sleep(for: .seconds(1))
      } catch {
        return
      }
      sourceActionHoldTask = nil
      guard holdsSourceActionOpen, !observedSourceActivity else { return }
      releaseSourceActionHold()
    }
  }

  private func handleSourceActionsMenuClosed() {
    guard !holdsSourceActionOpen else { return }
    onSourceActionsMenuClosed()
  }

  private func handleSourceActivityChange(hasActivity: Bool) {
    guard holdsSourceActionOpen else { return }

    if hasActivity {
      observedSourceActivity = true
      sourceActionHoldTask?.cancel()
      sourceActionHoldTask = nil
    } else if observedSourceActivity {
      releaseSourceActionHold()
    }
  }

  private func releaseSourceActionHold() {
    sourceActionHoldTask?.cancel()
    sourceActionHoldTask = nil

    guard holdsSourceActionOpen else { return }
    holdsSourceActionOpen = false
    observedSourceActivity = false
    popupPanel.endTransientInteraction()
  }

  private var sourceActivityRows: [InboxSourceActivityRow] {
    store.sourceConfigurations.flatMap { configuration in
      configuration.actions.compactMap { action in
        guard action.isBusy else { return nil }
        return InboxSourceActivityRow(
          source: configuration.source,
          action: action,
          presentation: sourcePresentation(for: configuration.source)
        )
      }
    }
    .sorted {
      if $0.source == $1.source { return $0.action.id < $1.action.id }
      return $0.source.localizedCaseInsensitiveCompare($1.source) == .orderedAscending
    }
  }

  private func sourcePresentation(for source: String) -> InboxSourcePresentation? {
    store.presentedItems.first { $0.source == source }?.item.source
  }

  private func sourceActivityView(
    _ activity: InboxSourceActivityRow,
    config: Config.InboxBuiltinConfig
  ) -> some View {
    HStack(spacing: 6) {
      ProgressView()
        .controlSize(.small)

      if let icon = activity.presentation?.icon, !icon.isEmpty {
        InboxSourceIconView(
          value: icon,
          color: color(activity.presentation?.color ?? config.popupMutedColorHex)
        )
      }

      Text(activity.source + " · " + activity.action.title)
        .lineLimit(1)

      Spacer(minLength: 4)
    }
    .font(.caption)
    .foregroundStyle(color(config.popupMutedColorHex))
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(color(config.popupItemBackgroundColorHex))
    .clipShape(RoundedRectangle(cornerRadius: 7))
  }

  private func itemView(
    _ presented: InboxPresentedItem,
    busySourceActions: [InboxAction],
    config: Config.InboxBuiltinConfig
  ) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      if config.groupBy != .source {
        let source = presented.item.source
        Button {
          store.markRead(presented)
        } label: {
          HStack(spacing: 4) {
            if let icon = source?.icon, !icon.isEmpty {
              InboxSourceIconView(
                value: icon,
                color: color(source?.color ?? config.popupMutedColorHex)
              )
            }
            Text(source?.name?.isEmpty == false ? source?.name ?? presented.source : presented.source)
          }
        }
        .buttonStyle(.plain)
        .font(.caption.weight(.semibold))
        .foregroundStyle(color(source?.color ?? config.popupMutedColorHex))
        .accessibilityHint("Marks this message as read")
      }

      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Button {
          store.toggleRead(presented)
        } label: {
          Label {
            Text(presented.isUnread ? "Mark as read" : "Mark as unread")
          } icon: {
            Circle()
              .fill(presented.isUnread ? severityColor(presented.item.resolvedSeverity) : .clear)
              .overlay {
                Circle().stroke(
                  color(config.popupMutedColorHex), lineWidth: presented.isUnread ? 0 : 1)
              }
              .frame(width: 7, height: 7)
              .frame(width: 14, height: 14)
              .contentShape(Rectangle())
          }
          .labelStyle(.iconOnly)
        }
        .buttonStyle(.plain)
        .help(presented.isUnread ? "Mark as read" : "Mark as unread")
        Button(presented.item.title) {
          store.markRead(presented)
        }
        .buttonStyle(.plain)
        .font(.system(size: 13, weight: presented.isUnread ? .semibold : .regular))
        .foregroundStyle(color(config.popupTitleColorHex))
        .accessibilityHint("Marks this message as read")
        Spacer(minLength: 4)
      }

      if let body = presented.item.body, !body.isEmpty {
        Button {
          store.markRead(presented)
        } label: {
          bodyText(body, format: presented.item.resolvedFormat)
        }
        .buttonStyle(.plain)
        .font(.system(size: 12))
        .foregroundStyle(
          color(config.popupTextColorHex)
        )
        .accessibilityHint("Marks this message as read")
      }

      let actions = presented.item.actions ?? []
      let itemURL = presented.item.url.flatMap(URL.init(string:))
      if !actions.isEmpty || itemURL != nil {
        HStack(spacing: 10) {
          ForEach(actions) { action in
            let presentation = InboxItemActionPresentation(
              action: action,
              busySourceAction: busySourceActions.first { $0.id == action.id }
            )

            switch presentation.style {
            case .progress:
              HStack(spacing: 4) {
                ProgressView()
                  .controlSize(.small)
                Text(presentation.title)
              }
              .foregroundStyle(color(config.popupMutedColorHex))
            case .status:
              Text(presentation.title)
                .foregroundStyle(color(config.popupMutedColorHex))
            case .button:
              Button(presentation.title) {
                store.markRead(presented)
                emitAction(
                  .inboxAction,
                  actionID: action.id,
                  source: presented.source,
                  targetWidgetID: presented.item.id
                )
              }
              .buttonStyle(.plain)
              .foregroundStyle(color(config.popupActionColorHex))
              .disabled(!presentation.isEnabled)
            }
          }

          if let itemURL {
            Button("Open") {
              store.markRead(presented)
              NSWorkspace.shared.open(itemURL)
            }
            .buttonStyle(.plain)
            .foregroundStyle(color(config.popupActionColorHex))
          }
        }
        .font(.caption)
      }
    }
    .padding(8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(color(config.popupItemBackgroundColorHex))
    .clipShape(RoundedRectangle(cornerRadius: 7))
    .contentShape(Rectangle())
    .contextMenu {
      Button(presented.isUnread ? "Mark as read" : "Mark as unread") {
        store.toggleRead(presented)
      }
      if presented.item.isDismissible {
        Divider()
        Button("Dismiss") { store.dismiss(presented) }
      }
    }
  }

  private func sourceGroupHeader(
    title: String,
    presentation: InboxSourcePresentation?,
    config: Config.InboxBuiltinConfig
  ) -> some View {
    HStack(spacing: 5) {
      if config.groupBy == .source, let icon = presentation?.icon, !icon.isEmpty {
        InboxSourceIconView(
          value: icon,
          color: color(presentation?.color ?? config.popupMutedColorHex)
        )
      }
      Text(title)
    }
    .font(.caption.weight(.semibold))
    .foregroundStyle(color(presentation?.color ?? config.popupMutedColorHex))
  }

  @ViewBuilder
  private func bodyText(_ body: String, format: InboxBodyFormat) -> some View {
    if format == .markdown,
      let attributed = try? AttributedString(
        markdown: body,
        options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
      )
    {
      Text(attributed)
    } else {
      Text(body)
    }
  }

  private func emitAction(
    _ event: WidgetEvent,
    actionID: String,
    source: String,
    targetWidgetID: String
  ) {
    Task {
      await eventHub.emitWidgetEvent(
        event,
        widgetID: "builtin_inbox",
        targetWidgetID: targetWidgetID,
        source: source,
        actionID: actionID
      )
    }
  }

  private func color(_ value: String?) -> Color {
    Color(hex: value ?? configStore.snapshot.theme.colors.text, snapshot: configStore.snapshot)
  }

  private func severityColor(_ severity: InboxSeverity) -> Color {
    let config = configStore.snapshot.builtins.inbox
    switch severity {
    case .info: return color(config.infoColorHex)
    case .success: return color(config.successColorHex)
    case .warning: return color(config.warningColorHex)
    case .error: return color(config.errorColorHex)
    }
  }
}

enum InboxItemActionStyle: Equatable {
  case button
  case progress
  case status
}

struct InboxItemActionPresentation: Equatable {
  let title: String
  let style: InboxItemActionStyle
  let isEnabled: Bool

  init(action: InboxAction, busySourceAction: InboxAction?) {
    if let busySourceAction, busySourceAction.isBusy {
      title = busySourceAction.title
      style = .status
      isEnabled = false
    } else if action.isBusy {
      title = action.title
      style = .progress
      isEnabled = false
    } else {
      title = action.title
      style = .button
      isEnabled = action.isEnabled
    }
  }
}

private struct InboxSourceActivityRow: Identifiable {
  let source: String
  let action: InboxAction
  let presentation: InboxSourcePresentation?

  var id: String { source + "\u{1f}" + action.id }
}

private struct InboxSourceIconView: View {
  let value: String
  let color: Color

  private var imageSource: WidgetImageSource? {
    value.hasPrefix("/") ? .path(value) : nil
  }

  var body: some View {
    if let imageSource {
      WidgetImageView(source: imageSource, size: 12, tint: color)
    } else {
      Text(value)
    }
  }
}
