import Foundation

/// Renders the native calendar anchor from one ordered field configuration.
final class CalendarRenderer {

  typealias Snapshot = CalendarNativeWidget.Snapshot

  let rootID: String
  private let formatterCache = FormattedDateFormatterCache()

  init(rootID: String) {
    self.rootID = rootID
  }

  /// Builds a row or column of independently styled date/time fields.
  func makeNodes(snapshot: Snapshot) -> [WidgetNodeState] {
    let config = snapshot.config
    let anchor = config.anchor
    let placement = Config.BuiltinWidgetPlacement(config.placement)
    let style = Config.BuiltinWidgetStyle(config.style)
    let contentID = "\(rootID)_fields"

    var nodes = [
      BuiltinNativeNodeFactory.makeRowContainerNode(
        rootID: rootID,
        placement: placement,
        style: style
      ),
      BuiltinNativeNodeFactory.makeChildItemNode(
        rootID: rootID,
        parentID: rootID,
        childID: "\(rootID)_icon",
        position: placement.position,
        order: 0,
        icon: style.icon,
        color: style.textColorHex
      ),
      makeContentContainer(
        layout: anchor.layout,
        contentID: contentID,
        placement: placement,
        spacing: anchor.spacing
      ),
    ]

    for (index, kind) in anchor.fields.enumerated() {
      if shouldInsertSeparator(before: index, anchor: anchor) {
        nodes.append(
          BuiltinNativeNodeFactory.makeChildItemNode(
            rootID: rootID,
            parentID: contentID,
            childID: "\(rootID)_separator_\(index)",
            position: placement.position,
            order: index * 2 - 1,
            text: anchor.separator,
            color: style.textColorHex
          )
        )
      }

      let field = anchor.field(kind)
      var node = BuiltinNativeNodeFactory.makeChildItemNode(
        rootID: rootID,
        parentID: contentID,
        childID: "\(rootID)_field_\(index)_\(kind.rawValue)",
        position: placement.position,
        order: index * 2,
        text: formatterCache.string(from: snapshot.now, format: field.format),
        color: field.textColorHex ?? style.textColorHex,
        labelFontSize: field.fontSize
      )
      node.labelFontFamily = field.fontFamily
      node.labelFontWeight = field.fontWeight.rawValue
      nodes.append(node)
    }

    return nodes
  }

  private func shouldInsertSeparator(
    before index: Int,
    anchor: Config.CalendarBuiltinConfig.Anchor
  ) -> Bool {
    anchor.layout == .row && index > 0 && !anchor.separator.isEmpty
  }

  private func makeContentContainer(
    layout: CalendarAnchorLayout,
    contentID: String,
    placement: Config.BuiltinWidgetPlacement,
    spacing: Double
  ) -> WidgetNodeState {
    switch layout {
    case .row:
      return BuiltinNativeNodeFactory.makeRowNode(
        rootID: rootID,
        parentID: rootID,
        rowID: contentID,
        position: placement.position,
        order: 1,
        spacing: spacing
      )
    case .column:
      return BuiltinNativeNodeFactory.makeColumnNode(
        rootID: rootID,
        parentID: rootID,
        columnID: contentID,
        position: placement.position,
        order: 1,
        spacing: spacing
      )
    }
  }
}
