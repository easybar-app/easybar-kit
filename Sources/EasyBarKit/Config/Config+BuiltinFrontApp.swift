import Foundation

extension Config {

  /// Built-in front app widget config.
  struct FrontAppBuiltinConfig: @unchecked Sendable {
    /// Front-app content settings.
    struct Content {
      var showIcon: Bool
      var showName: Bool
      var fallbackText: String
      var iconSize: Double
      var iconCornerRadius: Double
    }

    /// Shared placement settings.
    var placement: BuiltinWidgetPlacement
    /// Shared visual style settings.
    var style: BuiltinWidgetStyle
    /// Front-app-specific content settings.
    var content: Content

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

    var showIcon: Bool {
      get { content.showIcon }
      set { content.showIcon = newValue }
    }

    var showName: Bool {
      get { content.showName }
      set { content.showName = newValue }
    }

    var fallbackText: String {
      get { content.fallbackText }
      set { content.fallbackText = newValue }
    }

    var iconSize: Double {
      get { content.iconSize }
      set { content.iconSize = newValue }
    }

    var iconCornerRadius: Double {
      get { content.iconCornerRadius }
      set { content.iconCornerRadius = newValue }
    }

    /// Default front-app widget config.
    static let `default` = FrontAppBuiltinConfig(
      placement: .init(
        enabled: false,
        position: .left,
        order: 20
      ),
      style: .init(
        icon: "􀈔",
        textColorHex: "#ffffff",
        backgroundColorHex: "#1a1a1a",
        borderColorHex: "#333333",
        borderWidth: 1,
        cornerRadius: 8,
        marginX: 0,
        marginY: 0,
        paddingX: 8,
        paddingY: 4,
        spacing: 6,
        opacity: 1
      ),
      content: .init(
        showIcon: true,
        showName: true,
        fallbackText: "No App",
        iconSize: 14,
        iconCornerRadius: 4
      )
    )
  }

  /// Parses the built-in front app widget.
  func parseFrontAppBuiltin(from builtins: ConfigReader) throws {
    guard let frontApp = try builtins.optionalSection("front_app") else { return }

    let placement = try parseBuiltinPlacement(
      reader: frontApp,
      fallback: builtinFrontApp.placement
    )

    let style = try parseBuiltinStyle(
      reader: try frontApp.section("style"),
      fallback: builtinFrontApp.style
    )

    let content = try parseFrontAppContent(
      reader: try frontApp.section("content"),
      fallback: builtinFrontApp.content
    )

    builtinFrontApp = FrontAppBuiltinConfig(
      placement: placement,
      style: style,
      content: content
    )
  }

  /// Parses the front-app content block.
  private func parseFrontAppContent(
    reader: ConfigReader,
    fallback: FrontAppBuiltinConfig.Content
  ) throws -> FrontAppBuiltinConfig.Content {
    FrontAppBuiltinConfig.Content(
      showIcon: try reader.bool("show_icon", fallback: fallback.showIcon),
      showName: try reader.bool("show_name", fallback: fallback.showName),
      fallbackText: try reader.string("fallback_text", fallback: fallback.fallbackText),
      iconSize: try reader.double(
        "icon_size",
        fallback: fallback.iconSize,
        minimum: 0
      ),
      iconCornerRadius: try reader.double(
        "icon_corner_radius",
        fallback: fallback.iconCornerRadius,
        minimum: 0
      )
    )
  }
}
