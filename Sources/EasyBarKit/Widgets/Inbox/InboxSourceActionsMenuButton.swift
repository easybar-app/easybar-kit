import AppKit
import SwiftUI

/// AppKit-backed inbox source menu with explicit lifecycle hooks for hover-controlled popups.
@MainActor
struct InboxSourceActionsMenuButton: NSViewRepresentable {
  let configurations: [InboxSourceConfiguration]
  let tintColor: NSColor
  let popupPanel: WidgetPopupPanelController
  let onAction: (String, String) -> Void
  let onMenuClosed: () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }

  func makeNSView(context: Context) -> NSButton {
    let button = NSButton()
    button.image = NSImage(
      systemSymbolName: "ellipsis.circle",
      accessibilityDescription: "Inbox actions"
    )
    button.imagePosition = .imageOnly
    button.isBordered = false
    button.focusRingType = .none
    button.toolTip = "Inbox actions"
    button.target = context.coordinator
    button.action = #selector(Coordinator.showMenu(_:))
    button.setContentHuggingPriority(.required, for: .horizontal)
    button.setContentHuggingPriority(.required, for: .vertical)
    return button
  }

  func updateNSView(_ button: NSButton, context: Context) {
    context.coordinator.parent = self
    button.contentTintColor = tintColor
    button.isEnabled = !configurations.isEmpty
  }

  @MainActor
  final class Coordinator: NSObject {
    var parent: InboxSourceActionsMenuButton

    init(_ parent: InboxSourceActionsMenuButton) {
      self.parent = parent
    }

    @objc func showMenu(_ sender: NSButton) {
      let menu = makeMenu()
      guard !menu.items.isEmpty else { return }

      parent.popupPanel.beginTransientInteraction()
      menu.popUp(
        positioning: nil,
        at: NSPoint(x: sender.bounds.minX, y: sender.bounds.minY - 4),
        in: sender
      )
      parent.popupPanel.endTransientInteraction()

      Task { @MainActor [weak self] in
        self?.parent.onMenuClosed()
      }
    }

    @objc private func performAction(_ item: NSMenuItem) {
      guard let selection = item.representedObject as? InboxSourceActionSelection else { return }
      parent.onAction(selection.source, selection.actionID)
    }

    private func makeMenu() -> NSMenu {
      let menu = NSMenu(title: "Inbox actions")
      menu.autoenablesItems = false

      for configuration in parent.configurations {
        let sourceItem = NSMenuItem(
          title: configuration.source,
          action: nil,
          keyEquivalent: ""
        )
        let submenu = NSMenu(title: configuration.source)
        submenu.autoenablesItems = false

        for action in configuration.actions {
          submenu.addItem(makeMenuItem(for: action, source: configuration.source))
        }

        sourceItem.submenu = submenu
        menu.addItem(sourceItem)
      }

      return menu
    }

    private func makeMenuItem(for action: InboxAction, source: String) -> NSMenuItem {
      let item = NSMenuItem(
        title: action.title,
        action: action.hasChildren ? nil : #selector(performAction(_:)),
        keyEquivalent: ""
      )
      item.isEnabled = action.isEnabled && !action.isBusy

      if let children = action.children, !children.isEmpty {
        let submenu = NSMenu(title: action.title)
        submenu.autoenablesItems = false
        for child in children {
          submenu.addItem(makeMenuItem(for: child, source: source))
        }
        item.submenu = submenu
      } else {
        item.target = self
        item.representedObject = InboxSourceActionSelection(
          source: source,
          actionID: action.id
        )
      }

      return item
    }
  }
}

private final class InboxSourceActionSelection: NSObject {
  let source: String
  let actionID: String

  init(source: String, actionID: String) {
    self.source = source
    self.actionID = actionID
  }
}
