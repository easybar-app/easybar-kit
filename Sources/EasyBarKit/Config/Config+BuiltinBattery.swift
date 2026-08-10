import Foundation

extension Config {

  /// Battery color mode.
  enum BuiltinBatteryColorMode: String, CaseIterable {
    case dynamic
    case fixed
  }

  /// Battery percentage display mode.
  enum BuiltinBatteryDisplayMode: String, CaseIterable {
    case none
    case tooltip
    case expand
    case always
  }

  /// Battery severity colors.
  struct BuiltinBatteryColors {
    var highColorHex: String
    var mediumColorHex: String
    var lowColorHex: String
    var criticalColorHex: String
    var frameColorHex: String
    var overlayOutlineColorHex: String
    var chargingOverlayColorHex: String
    var externalPowerOverlayColorHex: String
    var onHoldOverlayColorHex: String
    var unavailableColorHex: String
  }

  /// Built-in battery widget config.
  struct BatteryBuiltinConfig: @unchecked Sendable {

    /// Battery content and display settings.
    struct Content {
      var unavailableText: String
      var iconSize: Double
      var colorMode: BuiltinBatteryColorMode
      var fixedColorHex: String?
      var displayMode: BuiltinBatteryDisplayMode
      var colors: BuiltinBatteryColors
    }

    /// Shared placement settings.
    var placement: BuiltinWidgetPlacement
    /// Shared visual style settings.
    var style: BuiltinWidgetStyle
    /// Battery-specific content settings.
    var content: Content
    /// Tooltip popup style settings.
    var popup: BuiltinPopupStyle

    var enabled: Bool {
      get { placement.enabled }
      set { placement.enabled = newValue }
    }

    var position: WidgetPosition {
      get { placement.position }
      set { placement.position = newValue }
    }

    var order: Int {
      get { placement.order }
      set { placement.order = newValue }
    }

    var unavailableText: String {
      get { content.unavailableText }
      set { content.unavailableText = newValue }
    }

    var iconSize: Double {
      get { content.iconSize }
      set { content.iconSize = newValue }
    }

    var colorMode: BuiltinBatteryColorMode {
      get { content.colorMode }
      set { content.colorMode = newValue }
    }

    var fixedColorHex: String? {
      get { content.fixedColorHex }
      set { content.fixedColorHex = newValue }
    }

    var displayMode: BuiltinBatteryDisplayMode {
      get { content.displayMode }
      set { content.displayMode = newValue }
    }

    var colors: BuiltinBatteryColors {
      get { content.colors }
      set { content.colors = newValue }
    }

    /// Default battery widget config.
    static let `default` = BatteryBuiltinConfig(
      placement: .init(
        enabled: true,
        position: .right,
        order: 20,
        group: nil
      ),
      style: .init(
        icon: "􀫯",
        textColorHex: "#cdd6f4",
        backgroundColorHex: "#00000000",
        borderColorHex: "#00000000",
        borderWidth: 0,
        cornerRadius: 8,
        marginX: 0,
        marginY: 0,
        paddingX: 4,
        paddingY: 0,
        spacing: 6,
        opacity: 1
      ),
      content: .init(
        unavailableText: "n/a",
        iconSize: 18,
        colorMode: .fixed,
        fixedColorHex: "#cdd6f4",
        displayMode: .expand,
        colors: .init(
          highColorHex: "#a6e3a1",
          mediumColorHex: "#f9e2af",
          lowColorHex: "#fab387",
          criticalColorHex: "#f38ba8",
          frameColorHex: "#6c7086",
          overlayOutlineColorHex: "#000000F0",
          chargingOverlayColorHex: "#FFFFFFFF",
          externalPowerOverlayColorHex: "#FFFFFFFF",
          onHoldOverlayColorHex: "#FFFFFFFF",
          unavailableColorHex: "#6c7086"
        )
      ),
      popup: .init(
        textColorHex: Config.builtinPopupDefaultTextColorHex,
        backgroundColorHex: Config.builtinPopupDefaultBackgroundColorHex,
        borderColorHex: Config.builtinPopupDefaultBorderColorHex,
        borderWidth: Config.builtinPopupDefaultBorderWidth,
        cornerRadius: Config.builtinPopupDefaultCornerRadius,
        paddingX: Config.builtinPopupDefaultPaddingX,
        paddingY: Config.builtinPopupDefaultPaddingY,
        marginX: Config.builtinPopupDefaultMarginX,
        marginY: Config.builtinPopupDefaultMarginY
      )
    )
  }

  /// Parses the built-in battery widget.
  func parseBatteryBuiltin(from builtins: ConfigReader) throws {
    guard let battery = try builtins.optionalSection("battery") else { return }

    let placement = try parseBuiltinPlacement(
      reader: battery,
      fallback: builtinBattery.placement
    )

    let style = try parseBuiltinStyle(
      reader: try battery.section("style"),
      fallback: builtinBattery.style
    )

    let content = try parseBatteryContent(
      reader: try battery.section("content"),
      colors: try battery.section("colors"),
      fallback: builtinBattery.content
    )

    let popup = try parseBuiltinPopupStyle(
      reader: try battery.section("tooltip"),
      fallback: builtinBattery.popup
    )

    builtinBattery = BatteryBuiltinConfig(
      placement: placement,
      style: style,
      content: content,
      popup: popup
    )
  }

  /// Parses the battery content and severity color settings.
  private func parseBatteryContent(
    reader: ConfigReader,
    colors: ConfigReader,
    fallback: BatteryBuiltinConfig.Content
  ) throws -> BatteryBuiltinConfig.Content {
    BatteryBuiltinConfig.Content(
      unavailableText: try reader.string("unavailable_text", fallback: fallback.unavailableText),
      iconSize: try reader.double(
        "icon_size",
        fallback: fallback.iconSize,
        minimum: 0
      ),
      colorMode: try reader.enum("color_mode", fallback: fallback.colorMode),
      fixedColorHex: try reader.optionalColor("fixed_color", fallback: fallback.fixedColorHex),
      displayMode: try reader.enum("display_mode", fallback: fallback.displayMode),
      colors: try parseBatteryColors(reader: colors, fallback: fallback.colors)
    )
  }

  /// Parses the battery severity color settings.
  private func parseBatteryColors(
    reader: ConfigReader,
    fallback: BuiltinBatteryColors
  ) throws -> BuiltinBatteryColors {
    BuiltinBatteryColors(
      highColorHex: try reader.color("high", fallback: fallback.highColorHex),
      mediumColorHex: try reader.color("medium", fallback: fallback.mediumColorHex),
      lowColorHex: try reader.color("low", fallback: fallback.lowColorHex),
      criticalColorHex: try reader.color("critical", fallback: fallback.criticalColorHex),
      frameColorHex: try reader.color("frame", fallback: fallback.frameColorHex),
      overlayOutlineColorHex: try reader.color(
        "overlay_outline",
        fallback: fallback.overlayOutlineColorHex
      ),
      chargingOverlayColorHex: try reader.color(
        "charging_overlay",
        fallback: fallback.chargingOverlayColorHex
      ),
      externalPowerOverlayColorHex: try reader.color(
        "external_power_overlay",
        fallback: fallback.externalPowerOverlayColorHex
      ),
      onHoldOverlayColorHex: try reader.color(
        "on_hold_overlay",
        fallback: fallback.onHoldOverlayColorHex
      ),
      unavailableColorHex: try reader.color("unavailable", fallback: fallback.unavailableColorHex)
    )
  }
}
