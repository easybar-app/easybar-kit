import AppKit
import SwiftUI

/// AppKit-backed inbox source menu with explicit lifecycle hooks for hover-controlled popups.
@MainActor
struct InboxSourceActionsMenuButton: NSViewRepresentable {
  /// The configurations for this inbox source actions menu button.
  let configurations: [InboxSourceConfiguration]
  /// The tint color for this inbox source actions menu button.
  let tintColor: NSColor
  /// The popup panel for this inbox source actions menu button.
  let popupPanel: WidgetPopupPanelController
  /// The on action for this inbox source actions menu button.
  let onAction: (String, String) -> Void
  /// The on menu closed for this inbox source actions menu button.
  let onMenuClosed: () -> Void

  /// Creates coordinator.
  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }

  /// Creates ns view.
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

  /// Updates ns view.
  func updateNSView(_ button: NSButton, context: Context) {
    context.coordinator.parent = self
    button.contentTintColor = tintColor
    button.isEnabled = !configurations.isEmpty
  }

  @MainActor
  /// Coordinates coordinator state and behavior.
  final class Coordinator: NSObject {
    var parent: InboxSourceActionsMenuButton

    /// Creates a coordinator.
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

    /// Creates menu.
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

    /// Creates menu item.
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

/// Coordinates inbox source action selection state and behavior.
private final class InboxSourceActionSelection: NSObject {
  let source: String
  let actionID: String

  /// Creates an inbox source action selection.
  init(source: String, actionID: String) {
    self.source = source
    self.actionID = actionID
  }
}
