import Foundation
import SwiftUI

extension Config {

  /// Built-in spaces widget config.
  struct SpacesBuiltinConfig: @unchecked Sendable {
    /// Spaces layout behavior settings.
    struct Layout {
      /// The spacing for this layout.
      var spacing: Double
      /// Whether the hide empty option is enabled for this layout.
      var hideEmpty: Bool
      /// The padding x for this layout.
      var paddingX: Double
      /// The padding y for this layout.
      var paddingY: Double
      /// The margin x for this layout.
      var marginX: Double
      /// The margin y for this layout.
      var marginY: Double
      /// The corner radius for this layout.
      var cornerRadius: Double
      /// The focused corner radius for this layout.
      var focusedCornerRadius: Double
      /// The focused scale for this layout.
      var focusedScale: Double
      /// The inactive opacity for this layout.
      var inactiveOpacity: Double
      /// The max icons for this layout.
      var maxIcons: Int
      /// Whether this layout shows label.
      var showLabel: Bool
      /// Whether this layout shows icons.
      var showIcons: Bool
      /// Whether this layout shows only focused label.
      var showOnlyFocusedLabel: Bool
      /// Whether the collapse inactive option is enabled for this layout.
      var collapseInactive: Bool
      /// The collapsed padding x for this layout.
      var collapsedPaddingX: Double
      /// The collapsed padding y for this layout.
      var collapsedPaddingY: Double
      /// Whether the click to focus space option is enabled for this layout.
      var clickToFocusSpace: Bool
      /// Whether the click to focus app option is enabled for this layout.
      var clickToFocusApp: Bool
    }

    /// Spaces label text settings.
    struct Text {
      /// The size for this text.
      var size: Double
      /// The weight for this text.
      var weight: String
      /// The focused color hex for this text.
      var focusedColorHex: String
      /// The inactive color hex for this text.
      var inactiveColorHex: String

      /// Resolved SwiftUI font weight.
      var resolvedWeight: Font.Weight {
        switch weight.lowercased() {
        case "ultralight": return .ultraLight
        case "thin": return .thin
        case "light": return .light
        case "regular": return .regular
        case "medium": return .medium
        case "bold": return .bold
        case "heavy": return .heavy
        case "black": return .black
        default: return .semibold
        }
      }
    }

    /// Spaces app-icon settings.
    struct Icons {
      /// The size for this icons.
      var size: Double
      /// The spacing for this icons.
      var spacing: Double
      /// The corner radius for this icons.
      var cornerRadius: Double
      /// The focused app size for this icons.
      var focusedAppSize: Double
      /// The border width for this icons.
      var borderWidth: Double
      /// The focused app border width for this icons.
      var focusedAppBorderWidth: Double
    }

    /// Spaces color settings.
    struct Colors {
      /// The active background hex for this colors.
      var activeBackgroundHex: String
      /// The inactive background hex for this colors.
      var inactiveBackgroundHex: String
      /// The active border hex for this colors.
      var activeBorderHex: String
      /// The inactive border hex for this colors.
      var inactiveBorderHex: String
      /// The focused app border hex for this colors.
      var focusedAppBorderHex: String
    }

    /// Shared placement settings.
    var placement: BuiltinWidgetPlacement
    /// Shared visual chrome settings.
    var style: BuiltinWidgetChromeStyle
    /// Layout behavior settings.
    var layout: Layout
    /// Text style settings.
    var text: Text
    /// Icon style settings.
    var icons: Icons
    /// Color settings.
    var colors: Colors

    /// Whether this spaces builtin config is enabled.
    var enabled: Bool {
      get { placement.enabled }
      set { placement.enabled = newValue }
    }

    /// The position for this spaces builtin config.
    var position: WidgetPosition {
      get { placement.position }
      set { placement.position = newValue }
    }

    /// The order for this spaces builtin config.
    var order: Int {
      get { placement.order }
      set { placement.order = newValue }
    }

    /// Default spaces widget config.
    static let `default` = SpacesBuiltinConfig(
      placement: .init(
        enabled: true,
        position: .left,
        order: 10
      ),
      style: .init(
        backgroundColorHex: "#00000000",
        borderColorHex: "#00000000",
        borderWidth: 0,
        cornerRadius: 0,
        marginX: 0,
        marginY: 0,
        paddingX: 0,
        paddingY: 0,
        spacing: 0,
        opacity: 1
      ),
      layout: .init(
        spacing: 8,
        hideEmpty: true,
        paddingX: 12,
        paddingY: 2,
        marginX: 4,
        marginY: 4,
        cornerRadius: 8,
        focusedCornerRadius: 8,
        focusedScale: 1.0,
        inactiveOpacity: 0.85,
        maxIcons: 4,
        showLabel: true,
        showIcons: true,
        showOnlyFocusedLabel: false,
        collapseInactive: false,
        collapsedPaddingX: 6,
        collapsedPaddingY: 4,
        clickToFocusSpace: true,
        clickToFocusApp: true
      ),
      text: .init(
        size: 12,
        weight: "semibold",
        focusedColorHex: "#d0d0d0",
        inactiveColorHex: "#d0d0d0"
      ),
      icons: .init(
        size: 20,
        spacing: 4,
        cornerRadius: 3,
        focusedAppSize: 28,
        borderWidth: 1,
        focusedAppBorderWidth: 1
      ),
      colors: .init(
        activeBackgroundHex: "#2b2b2b",
        inactiveBackgroundHex: "#1a1a1a",
        activeBorderHex: "#444444",
        inactiveBorderHex: "#00000000",
        focusedAppBorderHex: "#00000000"
      )
    )
  }

  /// Parses the built-in spaces widget.
  func parseSpacesBuiltin(from builtins: ConfigReader) throws {
    guard let spaces = try builtins.optionalSection("spaces") else { return }

    let placement = try parseBuiltinPlacement(
      reader: spaces,
      fallback: builtinSpaces.placement
    )

    let style = try parseBuiltinChromeStyle(
      reader: spaces,
      fallback: builtinSpaces.style
    )

    let layout = try parseSpacesLayout(
      reader: try spaces.section("layout"),
      fallback: builtinSpaces.layout
    )
    let text = try parseSpacesText(
      reader: try spaces.section("text"),
      fallback: builtinSpaces.text
    )
    let icons = try parseSpacesIcons(
      reader: try spaces.section("icons"),
      fallback: builtinSpaces.icons
    )
    let colors = try parseSpacesColors(
      reader: try spaces.section("colors"),
      fallback: builtinSpaces.colors
    )

    builtinSpaces = SpacesBuiltinConfig(
      placement: placement,
      style: style,
      layout: layout,
      text: text,
      icons: icons,
      colors: colors
    )
  }

  /// Parses the spaces layout block.
  private func parseSpacesLayout(
    reader: ConfigReader,
    fallback: SpacesBuiltinConfig.Layout
  ) throws -> SpacesBuiltinConfig.Layout {
    SpacesBuiltinConfig.Layout(
      spacing: try reader.double("spacing", fallback: fallback.spacing, minimum: 0),
      hideEmpty: try reader.bool("hide_empty", fallback: fallback.hideEmpty),
      paddingX: try reader.double("padding_x", fallback: fallback.paddingX, minimum: 0),
      paddingY: try reader.double("padding_y", fallback: fallback.paddingY, minimum: 0),
      marginX: try reader.double("margin_x", fallback: fallback.marginX),
      marginY: try reader.double("margin_y", fallback: fallback.marginY),
      cornerRadius: try reader.double("corner_radius", fallback: fallback.cornerRadius, minimum: 0),
      focusedCornerRadius: try reader.double(
        "focused_corner_radius",
        fallback: fallback.focusedCornerRadius,
        minimum: 0
      ),
      focusedScale: try reader.double(
        "focused_scale",
        fallback: fallback.focusedScale,
        minimum: 0
      ),
      inactiveOpacity: try reader.double(
        "inactive_opacity",
        fallback: fallback.inactiveOpacity,
        minimum: 0,
        maximum: 1
      ),
      maxIcons: try reader.int("max_icons", fallback: fallback.maxIcons, minimum: 0),
      showLabel: try reader.bool("show_label", fallback: fallback.showLabel),
      showIcons: try reader.bool("show_icons", fallback: fallback.showIcons),
      showOnlyFocusedLabel: try reader.bool(
        "show_only_focused_label",
        fallback: fallback.showOnlyFocusedLabel
      ),
      collapseInactive: try reader.bool("collapse_inactive", fallback: fallback.collapseInactive),
      collapsedPaddingX: try reader.double(
        "collapsed_padding_x",
        fallback: fallback.collapsedPaddingX,
        minimum: 0
      ),
      collapsedPaddingY: try reader.double(
        "collapsed_padding_y",
        fallback: fallback.collapsedPaddingY,
        minimum: 0
      ),
      clickToFocusSpace: try reader.bool(
        "click_to_focus_space",
        fallback: fallback.clickToFocusSpace
      ),
      clickToFocusApp: try reader.bool("click_to_focus_app", fallback: fallback.clickToFocusApp)
    )
  }

  /// Parses the spaces text block.
  private func parseSpacesText(
    reader: ConfigReader,
    fallback: SpacesBuiltinConfig.Text
  ) throws -> SpacesBuiltinConfig.Text {
    SpacesBuiltinConfig.Text(
      size: try reader.double("size", fallback: fallback.size, minimum: 0),
      weight: try validatedSpacesTextWeight(
        try reader.string("weight", fallback: fallback.weight),
        path: reader.path(for: "weight")
      ),
      focusedColorHex: try reader.color("focused_color", fallback: fallback.focusedColorHex),
      inactiveColorHex: try reader.color("inactive_color", fallback: fallback.inactiveColorHex)
    )
  }

  /// Parses the spaces icons block.
  private func parseSpacesIcons(
    reader: ConfigReader,
    fallback: SpacesBuiltinConfig.Icons
  ) throws -> SpacesBuiltinConfig.Icons {
    SpacesBuiltinConfig.Icons(
      size: try reader.double("size", fallback: fallback.size, minimum: 0),
      spacing: try reader.double("spacing", fallback: fallback.spacing, minimum: 0),
      cornerRadius: try reader.double("corner_radius", fallback: fallback.cornerRadius, minimum: 0),
      focusedAppSize: try reader.double(
        "focused_app_size",
        fallback: fallback.focusedAppSize,
        minimum: 0
      ),
      borderWidth: try reader.double("border_width", fallback: fallback.borderWidth, minimum: 0),
      focusedAppBorderWidth: try reader.double(
        "focused_app_border_width",
        fallback: fallback.focusedAppBorderWidth,
        minimum: 0
      )
    )
  }

  /// Parses the spaces colors block.
  private func parseSpacesColors(
    reader: ConfigReader,
    fallback: SpacesBuiltinConfig.Colors
  ) throws -> SpacesBuiltinConfig.Colors {
    SpacesBuiltinConfig.Colors(
      activeBackgroundHex: try reader.color(
        "active_background",
        fallback: fallback.activeBackgroundHex
      ),
      inactiveBackgroundHex: try reader.color(
        "inactive_background",
        fallback: fallback.inactiveBackgroundHex
      ),
      activeBorderHex: try reader.color("active_border", fallback: fallback.activeBorderHex),
      inactiveBorderHex: try reader.color("inactive_border", fallback: fallback.inactiveBorderHex),
      focusedAppBorderHex: try reader.color(
        "focused_app_border",
        fallback: fallback.focusedAppBorderHex
      )
    )
  }
}
