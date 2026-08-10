import Foundation

extension Config {

  /// Built-in AeroSpace mode widget config.
  struct AeroSpaceModeBuiltinConfig: @unchecked Sendable {
    /// Text and icon settings for the mode widget.
    struct Content {
      var showIcon: Bool
      var showText: Bool

      var hTilesIcon: String
      var vTilesIcon: String
      var hAccordionIcon: String
      var vAccordionIcon: String
      var floatingIcon: String
      var unknownIcon: String

      var hTilesText: String
      var vTilesText: String
      var hAccordionText: String
      var vAccordionText: String
      var floatingText: String
      var unknownText: String
    }

    /// Shared placement settings.
    var placement: BuiltinWidgetPlacement
    /// Text and visual chrome settings.
    var style: BuiltinWidgetTextStyle
    /// Mode-specific content settings.
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

    var showText: Bool {
      get { content.showText }
      set { content.showText = newValue }
    }

    var hTilesIcon: String {
      get { content.hTilesIcon }
      set { content.hTilesIcon = newValue }
    }

    var vTilesIcon: String {
      get { content.vTilesIcon }
      set { content.vTilesIcon = newValue }
    }

    var hAccordionIcon: String {
      get { content.hAccordionIcon }
      set { content.hAccordionIcon = newValue }
    }

    var vAccordionIcon: String {
      get { content.vAccordionIcon }
      set { content.vAccordionIcon = newValue }
    }

    var floatingIcon: String {
      get { content.floatingIcon }
      set { content.floatingIcon = newValue }
    }

    var unknownIcon: String {
      get { content.unknownIcon }
      set { content.unknownIcon = newValue }
    }

    var hTilesText: String {
      get { content.hTilesText }
      set { content.hTilesText = newValue }
    }

    var vTilesText: String {
      get { content.vTilesText }
      set { content.vTilesText = newValue }
    }

    var hAccordionText: String {
      get { content.hAccordionText }
      set { content.hAccordionText = newValue }
    }

    var vAccordionText: String {
      get { content.vAccordionText }
      set { content.vAccordionText = newValue }
    }

    var floatingText: String {
      get { content.floatingText }
      set { content.floatingText = newValue }
    }

    var unknownText: String {
      get { content.unknownText }
      set { content.unknownText = newValue }
    }

    /// Default AeroSpace mode widget config.
    static let `default` = AeroSpaceModeBuiltinConfig(
      placement: .init(
        enabled: false,
        position: .left,
        order: 30
      ),
      style: .init(
        textColorHex: "#ffffff",
        chrome: .init(
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
        )
      ),
      content: .init(
        showIcon: true,
        showText: false,
        hTilesIcon: "󰕴",
        vTilesIcon: "󰕳",
        hAccordionIcon: "󰖲",
        vAccordionIcon: "󰖳",
        floatingIcon: "󰹙",
        unknownIcon: "󰘎",
        hTilesText: "h_tiles",
        vTilesText: "v_tiles",
        hAccordionText: "h_accordion",
        vAccordionText: "v_accordion",
        floatingText: "floating",
        unknownText: "unknown"
      )
    )
  }

  /// Parses the built-in AeroSpace mode widget.
  func parseAeroSpaceModeBuiltin(from builtins: ConfigReader) throws {
    guard let aerospaceMode = try builtins.optionalSection("aerospace_mode") else { return }

    let placement = try parseBuiltinPlacement(
      reader: aerospaceMode,
      fallback: builtinAeroSpaceMode.placement
    )

    let style = try parseBuiltinTextStyle(
      reader: try aerospaceMode.section("style"),
      fallback: builtinAeroSpaceMode.style
    )

    let content = try parseAeroSpaceModeContent(
      reader: try aerospaceMode.section("content"),
      fallback: builtinAeroSpaceMode.content
    )

    builtinAeroSpaceMode = AeroSpaceModeBuiltinConfig(
      placement: placement,
      style: style,
      content: content
    )
  }

  /// Parses the AeroSpace mode content block.
  private func parseAeroSpaceModeContent(
    reader: ConfigReader,
    fallback: AeroSpaceModeBuiltinConfig.Content
  ) throws -> AeroSpaceModeBuiltinConfig.Content {
    AeroSpaceModeBuiltinConfig.Content(
      showIcon: try reader.bool("show_icon", fallback: fallback.showIcon),
      showText: try reader.bool("show_text", fallback: fallback.showText),
      hTilesIcon: try reader.string("h_tiles_icon", fallback: fallback.hTilesIcon),
      vTilesIcon: try reader.string("v_tiles_icon", fallback: fallback.vTilesIcon),
      hAccordionIcon: try reader.string("h_accordion_icon", fallback: fallback.hAccordionIcon),
      vAccordionIcon: try reader.string("v_accordion_icon", fallback: fallback.vAccordionIcon),
      floatingIcon: try reader.string("floating_icon", fallback: fallback.floatingIcon),
      unknownIcon: try reader.string("unknown_icon", fallback: fallback.unknownIcon),
      hTilesText: try reader.string("h_tiles_text", fallback: fallback.hTilesText),
      vTilesText: try reader.string("v_tiles_text", fallback: fallback.vTilesText),
      hAccordionText: try reader.string("h_accordion_text", fallback: fallback.hAccordionText),
      vAccordionText: try reader.string("v_accordion_text", fallback: fallback.vAccordionText),
      floatingText: try reader.string("floating_text", fallback: fallback.floatingText),
      unknownText: try reader.string("unknown_text", fallback: fallback.unknownText)
    )
  }
}
