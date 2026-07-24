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

    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("Inbox").font(.headline).foregroundStyle(color(config.popupTitleColorHex))
        Spacer()
        if store.unreadCount > 0 {
          Button("Mark all read") { store.markAllRead() }
            .buttonStyle(.plain)
            .foregroundStyle(color(config.popupMutedColorHex))
        }
        if !store.presentedItems.isEmpty {
          Button("Dismiss all") { store.dismissAll() }
            .buttonStyle(.plain)
            .foregroundStyle(color(config.popupMutedColorHex))
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
                itemView(item, config: config)
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
    .onChange(of: activities.map(\.id), initial: false) { _, activityIDs in
      handleSourceActivityChange(hasActivity: !activityIDs.isEmpty)
    }
    .onDisappear {
      releaseSourceActionHold()
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
        try await Task.sleep(nanoseconds: 1_000_000_000)
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
    config: Config.InboxBuiltinConfig
  ) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      if config.groupBy != .source {
        let source = presented.item.source
        HStack(spacing: 4) {
          if let icon = source?.icon, !icon.isEmpty {
            InboxSourceIconView(
              value: icon,
              color: color(source?.color ?? config.popupMutedColorHex)
            )
          }
          Text(source?.name?.isEmpty == false ? source?.name ?? presented.source : presented.source)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(color(source?.color ?? config.popupMutedColorHex))
        .onTapGesture { store.markRead(presented) }
      }

      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Button {
          store.toggleRead(presented)
        } label: {
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
        .buttonStyle(.plain)
        .help(presented.isUnread ? "Mark as read" : "Mark as unread")
        Text(presented.item.title)
          .font(.system(size: 13, weight: presented.isUnread ? .semibold : .regular))
          .foregroundStyle(color(config.popupTitleColorHex))
          .onTapGesture { store.markRead(presented) }
        Spacer(minLength: 4)
      }

      if let body = presented.item.body, !body.isEmpty {
        bodyText(body, format: presented.item.resolvedFormat)
          .font(.system(size: 12))
          .foregroundStyle(
            color(config.popupTextColorHex)
          )
          .onTapGesture { store.markRead(presented) }
      }

      if let actions = presented.item.actions, !actions.isEmpty {
        HStack(spacing: 10) {
          ForEach(actions) { action in
            if action.isBusy {
              HStack(spacing: 4) {
                ProgressView()
                  .controlSize(.small)
                Text(action.title)
              }
              .foregroundStyle(color(config.popupMutedColorHex))
            } else {
              Button(action.title) {
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
              .disabled(!action.isEnabled)
            }
          }
        }
        .font(.caption)
      }

      if let value = presented.item.url, let url = URL(string: value) {
        Button("Open") {
          store.markRead(presented)
          NSWorkspace.shared.open(url)
        }
        .buttonStyle(.plain)
        .font(.caption)
        .foregroundStyle(color(config.popupActionColorHex))
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
