import Foundation

extension Config {

  /// Built-in AeroSpace mode widget config.
  struct AeroSpaceModeBuiltinConfig: @unchecked Sendable {
    /// Text and icon settings for the mode widget.
    struct Content {
      /// Whether this content shows icon.
      var showIcon: Bool
      /// Whether this content shows text.
      var showText: Bool

      /// The h tiles icon for this content.
      var hTilesIcon: String
      /// The v tiles icon for this content.
      var vTilesIcon: String
      /// The h accordion icon for this content.
      var hAccordionIcon: String
      /// The v accordion icon for this content.
      var vAccordionIcon: String
      /// The floating icon for this content.
      var floatingIcon: String
      /// The unknown icon for this content.
      var unknownIcon: String

      /// The h tiles text for this content.
      var hTilesText: String
      /// The v tiles text for this content.
      var vTilesText: String
      /// The h accordion text for this content.
      var hAccordionText: String
      /// The v accordion text for this content.
      var vAccordionText: String
      /// The floating text for this content.
      var floatingText: String
      /// The unknown text for this content.
      var unknownText: String
    }

    /// Shared placement settings.
    var placement: BuiltinWidgetPlacement
    /// Text and visual chrome settings.
    var style: BuiltinWidgetTextStyle
    /// Mode-specific content settings.
    var content: Content

    /// Whether this AeroSpace mode builtin config is enabled.
    var enabled: Bool {
      get { placement.enabled }
      set { placement.enabled = newValue }
    }

    /// The position for this AeroSpace mode builtin config.
    var position: WidgetPosition {
      get { placement.position }
      set { placement.position = newValue }
    }

    /// The order for this AeroSpace mode builtin config.
    var order: Int {
      get { placement.order }
      set { placement.order = newValue }
    }

    /// Whether this AeroSpace mode builtin config shows icon.
    var showIcon: Bool {
      get { content.showIcon }
      set { content.showIcon = newValue }
    }

    /// Whether this AeroSpace mode builtin config shows text.
    var showText: Bool {
      get { content.showText }
      set { content.showText = newValue }
    }

    /// The h tiles icon for this AeroSpace mode builtin config.
    var hTilesIcon: String {
      get { content.hTilesIcon }
      set { content.hTilesIcon = newValue }
    }

    /// The v tiles icon for this AeroSpace mode builtin config.
    var vTilesIcon: String {
      get { content.vTilesIcon }
      set { content.vTilesIcon = newValue }
    }

    /// The h accordion icon for this AeroSpace mode builtin config.
    var hAccordionIcon: String {
      get { content.hAccordionIcon }
      set { content.hAccordionIcon = newValue }
    }

    /// The v accordion icon for this AeroSpace mode builtin config.
    var vAccordionIcon: String {
      get { content.vAccordionIcon }
      set { content.vAccordionIcon = newValue }
    }

    /// The floating icon for this AeroSpace mode builtin config.
    var floatingIcon: String {
      get { content.floatingIcon }
      set { content.floatingIcon = newValue }
    }

    /// The unknown icon for this AeroSpace mode builtin config.
    var unknownIcon: String {
      get { content.unknownIcon }
      set { content.unknownIcon = newValue }
    }

    /// The h tiles text for this AeroSpace mode builtin config.
    var hTilesText: String {
      get { content.hTilesText }
      set { content.hTilesText = newValue }
    }

    /// The v tiles text for this AeroSpace mode builtin config.
    var vTilesText: String {
      get { content.vTilesText }
      set { content.vTilesText = newValue }
    }

    /// The h accordion text for this AeroSpace mode builtin config.
    var hAccordionText: String {
      get { content.hAccordionText }
      set { content.hAccordionText = newValue }
    }

    /// The v accordion text for this AeroSpace mode builtin config.
    var vAccordionText: String {
      get { content.vAccordionText }
      set { content.vAccordionText = newValue }
    }

    /// The floating text for this AeroSpace mode builtin config.
    var floatingText: String {
      get { content.floatingText }
      set { content.floatingText = newValue }
    }

    /// The unknown text for this AeroSpace mode builtin config.
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
