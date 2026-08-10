import Foundation

/// Internal lifecycle contract implemented by EasyBarKit-owned built-in surfaces.
///
/// Lua packages are the public widget extension mechanism; this protocol is intentionally internal.
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

  /// Clears all rendered nodes owned by this built-in surface.
  func clearNodes() {
    applyNodes([])
  }

  /// Applies the latest rendered nodes owned by this built-in surface.
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
