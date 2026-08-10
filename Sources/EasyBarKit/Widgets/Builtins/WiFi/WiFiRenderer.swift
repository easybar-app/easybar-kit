import Foundation

/// Renders the native Wi-Fi widget tree from a Wi-Fi snapshot.
struct WiFiRenderer {

  typealias Snapshot = WiFiNativeWidget.Snapshot

  private enum DetailLayout {
    static let rowSpacing: Double = 2
    static let columnSpacing: Double = 8
  }

  let rootID: String

  /// Builds the Wi-Fi nodes for the current snapshot.
  func makeNodes(snapshot: Snapshot) -> [WidgetNodeState] {
    var nodes = makeAnchorNodes(snapshot: snapshot)

    switch snapshot.content {
    case .icon:
      break
    case .inline(let text):
      appendInlineText(
        text,
        snapshot: snapshot,
        to: &nodes
      )
    case .details(let rows):
      appendPopupDetailGrid(
        rows: rows,
        snapshot: snapshot,
        to: &nodes
      )
    }

    return nodes
  }
}

// MARK: - Inline Layout

extension WiFiRenderer {
  /// Appends one inline text node next to the Wi-Fi signal bars.
  private func appendInlineText(
    _ text: String,
    snapshot: Snapshot,
    to nodes: inout [WidgetNodeState]
  ) {
    guard snapshot.inlineContentVisible, !text.isEmpty else { return }

    nodes.append(
      BuiltinNativeNodeFactory.makeChildItemNode(
        rootID: rootID,
        parentID: rootID,
        childID: "\(rootID)_label",
        position: snapshot.config.placement.position,
        order: 1,
        text: text,
        color: snapshot.config.inlineTextColorHex,
        spacing: 4
      )
    )
  }
}

// MARK: - Popup Layout

extension WiFiRenderer {
  /// Appends popup content as two real columns: labels and values.
  ///
  /// Popup detail nodes must stay visible in the widget tree. The generic popup
  /// controller decides when the panel is presented; hiding these nodes here
  /// makes the panel open with empty content on the first hover.
  private func appendPopupDetailGrid(
    rows: [WiFiPresentation.DetailRow],
    snapshot: Snapshot,
    to nodes: inout [WidgetNodeState]
  ) {
    guard !rows.isEmpty else { return }

    let popup = snapshot.config.popup
    let gridID = "\(rootID)_popup_details"

    var popupNode = BuiltinNativeNodeFactory.makePopupContentNode(
      rootID: rootID,
      contentID: gridID,
      kind: .row,
      position: snapshot.config.placement.position,
      order: 0,
      visible: true,
      paddingX: popup.paddingX,
      paddingY: popup.paddingY,
      spacing: DetailLayout.columnSpacing,
      backgroundColor: popup.backgroundColorHex,
      borderColor: popup.borderColorHex,
      borderWidth: popup.borderWidth,
      cornerRadius: popup.cornerRadius,
      opacity: 1
    )
    popupNode.marginX = popup.marginX
    popupNode.marginY = popup.marginY
    nodes.append(popupNode)

    appendDetailColumns(
      rows: rows,
      parentID: gridID,
      idPrefix: "\(rootID)_popup_detail",
      position: snapshot.config.placement.position,
      color: popup.textColorHex ?? snapshot.config.inlineTextColorHex,
      to: &nodes
    )
  }
}

// MARK: - Shared Nodes

extension WiFiRenderer {
  /// Creates the always-visible Wi-Fi anchor nodes.
  private func makeAnchorNodes(snapshot: Snapshot) -> [WidgetNodeState] {
    var rootNode = BuiltinNativeNodeFactory.makeRowContainerNode(
      rootID: rootID,
      placement: snapshot.config.placement,
      style: snapshot.config.style.widgetStyle()
    )
    rootNode.popupPresented = snapshot.detailsContentVisible

    return [
      rootNode,

      BuiltinNativeNodeFactory.makeChildWiFiIndicatorNode(
        rootID: rootID,
        parentID: rootID,
        childID: "\(rootID)_icon",
        position: snapshot.config.placement.position,
        order: 0,
        signalLevel: snapshot.signalLevel,
        state: snapshot.visualState.rawValue,
        activeColor: snapshot.activeColorHex,
        inactiveColor: snapshot.inactiveColorHex,
        width: 20,
        height: 13
      ),
    ]
  }

  /// Appends one label column and one value column under the given parent row.
  private func appendDetailColumns(
    rows: [WiFiPresentation.DetailRow],
    parentID: String,
    idPrefix: String,
    position: WidgetPosition,
    color: String?,
    to nodes: inout [WidgetNodeState]
  ) {
    let labelColumnID = "\(idPrefix)_labels"
    let valueColumnID = "\(idPrefix)_values"

    nodes.append(
      BuiltinNativeNodeFactory.makeColumnNode(
        rootID: rootID,
        parentID: parentID,
        columnID: labelColumnID,
        position: position,
        order: 0,
        spacing: DetailLayout.rowSpacing
      )
    )

    nodes.append(
      BuiltinNativeNodeFactory.makeColumnNode(
        rootID: rootID,
        parentID: parentID,
        columnID: valueColumnID,
        position: position,
        order: 1,
        spacing: DetailLayout.rowSpacing
      )
    )

    for (index, row) in rows.enumerated() {
      nodes.append(
        BuiltinNativeNodeFactory.makeChildItemNode(
          rootID: rootID,
          parentID: labelColumnID,
          childID: "\(idPrefix)_label_\(index)",
          position: position,
          order: index,
          text: "\(row.labelText):",
          color: color,
          visible: true,
          spacing: 0
        )
      )

      nodes.append(
        BuiltinNativeNodeFactory.makeChildItemNode(
          rootID: rootID,
          parentID: valueColumnID,
          childID: "\(idPrefix)_value_\(index)",
          position: position,
          order: index,
          text: row.valueText,
          color: color,
          visible: true,
          spacing: 0
        )
      )
    }
  }
}
