import Foundation

/// Lifecycle contract implemented by all native widgets.
@MainActor
protocol NativeWidget: AnyObject {
  var rootID: String { get }
  var widgetStore: WidgetStore { get }
  var appEventSubscriptions: Set<String> { get }
  /// Starts the widget.
  func start()
  /// Stops the widget and clears rendered state.
  func stop()
  /// Reloads configuration.
  func reload()
}

extension NativeWidget {
  var appEventSubscriptions: Set<String> {
    return []
  }

  /// Reloads configuration.
  func reload() {
    stop()
    start()
  }

  /// Clears all rendered nodes owned by this native widget.
  func clearNodes() {
    applyNodes([])
  }

  /// Applies the latest rendered nodes owned by this native widget.
  func applyNodes(_ nodes: [WidgetNodeState]) {
    var nodes = nodes
    if let rootIndex = nodes.firstIndex(where: { $0.id == rootID }) {
      nodes[rootIndex].contextMenu = NativeWidgetContextMenu.appendingCommonActions(
        to: nodes[rootIndex].contextMenu
      )
    }
    widgetStore.apply(owner: .native(root: rootID), nodes: nodes)
  }
}
