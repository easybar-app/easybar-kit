import Foundation

/// Actions shared by every native widget context menu.
enum NativeWidgetContextMenuAction: String {
  case reload = "native_widget.reload"
  case disable = "native_widget.disable"
}

enum NativeWidgetContextMenu {
  /// Appends the common native-widget controls to an optional widget-specific menu.
  static func appendingCommonActions(
    to items: [WidgetContextMenuItem]?
  ) -> [WidgetContextMenuItem] {
    var result = items ?? []
    if needsCommonActionSeparator(result) {
      result.append(WidgetContextMenuItem(separator: true))
    }
    result.append(
      WidgetContextMenuItem(
        id: NativeWidgetContextMenuAction.reload.rawValue,
        title: "Reload Widget"
      )
    )
    result.append(
      WidgetContextMenuItem(
        id: NativeWidgetContextMenuAction.disable.rawValue,
        title: "Disable Widget"
      )
    )
    return result
  }

  private static func needsCommonActionSeparator(_ items: [WidgetContextMenuItem]) -> Bool {
    !items.isEmpty && items.last?.separator != true
  }
}
