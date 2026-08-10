import Foundation

/// Renders the native battery widget tree from a battery snapshot.
struct BatteryRenderer {

  typealias Snapshot = BatteryNativeWidget.Snapshot

  let rootID: String

  /// Tunable battery fill metrics.
  ///
  /// These values are relative to the symbol font size and control how the custom
  /// inner fill sits inside the `battery.0percent` shell.
  ///
  /// Tweak these first when the fill looks too large, too small, or slightly off-center:
  /// - `canvasWidthFactor`
  /// - `canvasHeightFactor`
  /// - `fillWidthFactor`
  /// - `fillHeightFactor`
  /// - `fillOffsetXFactor`
  /// - `fillOffsetYFactor`
  /// - `fillCornerRadiusFactor`
  /// - `minimumVisibleFillFactor`
  private enum BatteryFillMetrics {
    static let canvasWidthFactor = 1.52
    static let canvasHeightFactor = 0.90
    static let fillWidthFactor = 0.66
    static let fillHeightFactor = 0.36
    static let fillOffsetXFactor = 0.1
    static let fillOffsetYFactor = 0.0
    static let fillCornerRadiusFactor = 0.10
    static let minimumVisibleFillFactor = 0.08
  }

  /// Builds the battery nodes for the current snapshot.
  func makeNodes(snapshot: Snapshot) -> [WidgetNodeState] {
    switch snapshot.config.displayMode {
    case .tooltip:
      return makeTooltipNodes(snapshot: snapshot)
    case .none, .expand, .always:
      return makeInlineNodes(snapshot: snapshot)
    }
  }
}

// MARK: - Inline Layout

extension BatteryRenderer {

  /// Builds the inline battery layout.
  private func makeInlineNodes(snapshot: Snapshot) -> [WidgetNodeState] {
    let config = snapshot.config

    return [
      BuiltinNativeNodeFactory.makeRowContainerNode(
        rootID: rootID,
        placement: snapshot.placement,
        style: snapshot.style
      ),

      makeBatteryIconNode(
        snapshot: snapshot,
        parentID: rootID,
        childID: "\(rootID)_icon",
        order: 0,
        fontSize: config.iconSize
      ),

      BuiltinNativeNodeFactory.makeChildItemNode(
        rootID: rootID,
        parentID: rootID,
        childID: "\(rootID)_label",
        position: snapshot.placement.position,
        order: 1,
        text: snapshot.showLabel ? snapshot.text : "",
        color: snapshot.colorHex,
        visible: snapshot.showLabel && !snapshot.text.isEmpty,
        spacing: 4
      ),
    ]
  }
}

// MARK: - Tooltip Layout

extension BatteryRenderer {

  /// Builds the tooltip popup layout.
  private func makeTooltipNodes(snapshot: Snapshot) -> [WidgetNodeState] {
    let popup = snapshot.config.popup
    var popupNode = BuiltinNativeNodeFactory.makePopupContentNode(
      rootID: rootID,
      contentID: "\(rootID)_popup",
      kind: .column,
      position: snapshot.placement.position,
      order: 0,
      visible: !snapshot.text.isEmpty,
      paddingX: popup.paddingX,
      paddingY: popup.paddingY,
      spacing: 4,
      backgroundColor: popup.backgroundColorHex,
      borderColor: popup.borderColorHex,
      borderWidth: popup.borderWidth,
      cornerRadius: popup.cornerRadius,
      opacity: 1
    )
    popupNode.marginX = popup.marginX
    popupNode.marginY = popup.marginY

    return [
      BuiltinNativeNodeFactory.makeRowContainerNode(
        rootID: rootID,
        placement: snapshot.placement,
        style: snapshot.style
      ),

      makeBatteryIconNode(
        snapshot: snapshot,
        parentID: rootID,
        childID: "\(rootID)_icon",
        order: 0,
        fontSize: snapshot.config.iconSize
      ),

      popupNode,

      BuiltinNativeNodeFactory.makeChildItemNode(
        rootID: rootID,
        parentID: "\(rootID)_popup",
        childID: "\(rootID)_popup_text",
        position: snapshot.placement.position,
        order: 0,
        text: snapshot.text,
        color: popup.textColorHex ?? snapshot.colorHex ?? snapshot.style.textColorHex,
        visible: !snapshot.text.isEmpty
      ),
    ]
  }
}

// MARK: - Node Building

extension BatteryRenderer {

  /// Builds the battery icon item node with custom inner fill metadata.
  private func makeBatteryIconNode(
    snapshot: Snapshot,
    parentID: String,
    childID: String,
    order: Int,
    fontSize: Double
  ) -> WidgetNodeState {
    BuiltinNativeNodeFactory.makeChildItemNode(
      rootID: rootID,
      parentID: parentID,
      childID: childID,
      position: snapshot.placement.position,
      order: order,
      icon: snapshot.isUnavailable ? snapshot.style.icon : "",
      color: snapshot.colorHex,
      symbolName: resolvedBatterySymbol(unavailable: snapshot.isUnavailable),
      symbolSecondaryColor: resolvedBatteryFrameColor(snapshot: snapshot),
      symbolOverlayName: resolvedBatteryOverlaySymbol(snapshot: snapshot),
      symbolOverlayColor: resolvedBatteryOverlayColor(snapshot: snapshot),
      symbolOverlayBackdropColor: resolvedBatteryOverlayBackdropColor(snapshot: snapshot),
      symbolOverlayScale: resolvedBatteryOverlayScale(snapshot: snapshot),
      symbolOverlayBackdropScale: resolvedBatteryOverlayBackdropScale(snapshot: snapshot),
      symbolOverlayOffsetX: resolvedBatteryOverlayOffsetX(snapshot: snapshot),
      symbolOverlayOffsetY: resolvedBatteryOverlayOffsetY(snapshot: snapshot),
      symbolFillFraction: snapshot.isUnavailable ? nil : snapshot.fillFraction,
      symbolFillWidthFactor: snapshot.isUnavailable ? nil : BatteryFillMetrics.fillWidthFactor,
      symbolFillHeightFactor: snapshot.isUnavailable ? nil : BatteryFillMetrics.fillHeightFactor,
      symbolFillOffsetXFactor: snapshot.isUnavailable ? nil : BatteryFillMetrics.fillOffsetXFactor,
      symbolFillOffsetYFactor: snapshot.isUnavailable ? nil : BatteryFillMetrics.fillOffsetYFactor,
      symbolFillCornerRadiusFactor: snapshot.isUnavailable
        ? nil
        : BatteryFillMetrics.fillCornerRadiusFactor,
      symbolFillMinimumVisibleWidthFactor: snapshot.isUnavailable
        ? nil
        : BatteryFillMetrics.minimumVisibleFillFactor,
      symbolCanvasWidthFactor: snapshot.isUnavailable ? nil : BatteryFillMetrics.canvasWidthFactor,
      symbolCanvasHeightFactor: snapshot.isUnavailable
        ? nil : BatteryFillMetrics.canvasHeightFactor,
      fontSize: fontSize
    )
  }
}

// MARK: - Icon Logic

extension BatteryRenderer {

  /// Resolves the base SF Symbol for the current battery shell.
  fileprivate func resolvedBatterySymbol(unavailable: Bool) -> String? {
    guard !unavailable else { return nil }
    return "battery.0percent"
  }

  /// Resolves the overlay symbol for charging, on-hold, and external-power states.
  fileprivate func resolvedBatteryOverlaySymbol(snapshot: Snapshot) -> String? {
    guard !snapshot.isUnavailable else { return nil }

    if snapshot.charging {
      return "bolt.fill"
    }

    if snapshot.onHold {
      return "pause.fill"
    }

    if snapshot.onExternalPower {
      return "powerplug.portrait"
    }

    return nil
  }

  /// Returns the overlay scale for the charging bolt, on-hold pause, or plug.
  fileprivate func resolvedBatteryOverlayScale(snapshot: Snapshot) -> Double? {
    if snapshot.charging {
      return 0.40
    }

    if snapshot.onHold {
      return 0.40
    }

    if snapshot.onExternalPower {
      return 0.54
    }

    return nil
  }

  /// Returns the backdrop scale used to create a soft outline around the overlay.
  fileprivate func resolvedBatteryOverlayBackdropScale(snapshot: Snapshot) -> Double? {
    if snapshot.charging {
      return 0.40
    }

    if snapshot.onHold {
      return 0.40
    }

    if snapshot.onExternalPower {
      return 0.44
    }

    return nil
  }

  /// Returns the horizontal overlay offset used to visually center the overlay.
  fileprivate func resolvedBatteryOverlayOffsetX(snapshot: Snapshot) -> Double? {
    if snapshot.charging {
      return -1
    }

    if snapshot.onHold {
      return -1
    }

    if snapshot.onExternalPower {
      return -1
    }

    return nil
  }

  /// Returns the vertical overlay offset for the charging bolt, on-hold pause, or plug.
  fileprivate func resolvedBatteryOverlayOffsetY(snapshot: Snapshot) -> Double? {
    if snapshot.charging {
      return -0.35
    }

    if snapshot.onHold {
      return -0.2
    }

    if snapshot.onExternalPower {
      return -0.14
    }

    return nil
  }

  /// Returns the frame color used to visually separate the overlay from the battery.
  fileprivate func resolvedBatteryFrameColor(snapshot: Snapshot) -> String? {
    guard !snapshot.isUnavailable else { return nil }
    return snapshot.config.colors.frameColorHex
  }

  /// Returns the color of the charging bolt, on-hold pause, or external-power plug.
  fileprivate func resolvedBatteryOverlayColor(snapshot: Snapshot) -> String? {
    if snapshot.charging {
      return snapshot.config.colors.chargingOverlayColorHex
    }

    if snapshot.onHold {
      return snapshot.config.colors.onHoldOverlayColorHex
    }

    if snapshot.onExternalPower {
      return snapshot.config.colors.externalPowerOverlayColorHex
    }

    return nil
  }

  /// Returns the border color behind the overlay to improve contrast.
  fileprivate func resolvedBatteryOverlayBackdropColor(snapshot: Snapshot) -> String? {
    guard snapshot.charging || snapshot.onHold || snapshot.onExternalPower else { return nil }
    return snapshot.config.colors.overlayOutlineColorHex
  }
}
