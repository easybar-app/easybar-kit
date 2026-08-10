import Foundation

extension Config {

  /// Wi-Fi content mode.
  enum BuiltinWiFiContentMode: String, CaseIterable {
    case icon
    case inline
    case details
  }

  /// Wi-Fi content visibility timing.
  enum BuiltinWiFiContentSurface: String, CaseIterable {
    case always
    case hover
  }

  /// Wi-Fi inline text style.
  struct BuiltinWiFiInline {
    var textColorHex: String
  }

  /// Wi-Fi detail field toggles.
  struct BuiltinWiFiFields {
    var ssid: Bool
    var ipv4Address: Bool
    var ipv6Address: Bool
    var bssid: Bool
    var interfaceName: Bool
    var hardwareAddress: Bool
    var power: Bool
    var serviceActive: Bool
    var rssi: Bool
    var noise: Bool
    var snr: Bool
    var linkQuality: Bool
    var txRate: Bool
    var channel: Bool
    var channelBand: Bool
    var channelWidth: Bool
    var security: Bool
    var phyMode: Bool
    var interfaceMode: Bool
    var countryCode: Bool
    var roaming: Bool
    var ssidChangedAt: Bool
    var interfaceChangedAt: Bool

    /// Returns whether at least one detail field is enabled.
    var hasEnabledField: Bool {
      BuiltinWiFiFieldCatalog.fields.contains { self[keyPath: $0.keyPath] }
    }
  }

  /// Built-in Wi-Fi widget config.
  struct WiFiBuiltinConfig: @unchecked Sendable {
    /// Wi-Fi content and color settings.
    struct Content {
      var mode: BuiltinWiFiContentMode
      var surface: BuiltinWiFiContentSurface
      var inlineSeparator: String
      var disconnectedText: String
      var deniedText: String
      var activeColorHex: String
      var inactiveColorHex: String
    }

    /// Shared placement settings.
    var placement: BuiltinWidgetPlacement
    /// Shared visual chrome settings.
    var style: BuiltinWidgetChromeStyle
    /// Wi-Fi-specific content settings.
    var content: Content
    /// Inline text style.
    var inline: BuiltinWiFiInline
    /// Detail field toggles.
    var fields: BuiltinWiFiFields
    /// Popup style for Wi-Fi details mode.
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

    var mode: BuiltinWiFiContentMode {
      get { content.mode }
      set { content.mode = newValue }
    }

    var surface: BuiltinWiFiContentSurface {
      get { content.surface }
      set { content.surface = newValue }
    }

    var inlineSeparator: String {
      get { content.inlineSeparator }
      set { content.inlineSeparator = newValue }
    }

    var disconnectedText: String {
      get { content.disconnectedText }
      set { content.disconnectedText = newValue }
    }

    var deniedText: String {
      get { content.deniedText }
      set { content.deniedText = newValue }
    }

    var activeColorHex: String {
      get { content.activeColorHex }
      set { content.activeColorHex = newValue }
    }

    var inactiveColorHex: String {
      get { content.inactiveColorHex }
      set { content.inactiveColorHex = newValue }
    }

    var inlineTextColorHex: String {
      get { inline.textColorHex }
      set { inline.textColorHex = newValue }
    }

    /// Default Wi-Fi widget config.
    static let `default` = WiFiBuiltinConfig(
      placement: .init(
        enabled: true,
        position: .right,
        order: 30,
        group: nil
      ),
      style: .init(
        backgroundColorHex: "#00000000",
        borderColorHex: "#00000000",
        borderWidth: 0,
        cornerRadius: 8,
        marginX: 0,
        marginY: 0,
        paddingX: 8,
        paddingY: 0,
        spacing: 6,
        opacity: 1
      ),
      content: .init(
        mode: .icon,
        surface: .hover,
        inlineSeparator: " | ",
        disconnectedText: "disconnected",
        deniedText: "denied",
        activeColorHex: "#cdd6f4",
        inactiveColorHex: "#6c7086"
      ),
      inline: .init(
        textColorHex: "#ffffff"
      ),
      fields: .init(
        ssid: false,
        ipv4Address: false,
        ipv6Address: false,
        bssid: false,
        interfaceName: false,
        hardwareAddress: false,
        power: false,
        serviceActive: false,
        rssi: false,
        noise: false,
        snr: false,
        linkQuality: false,
        txRate: false,
        channel: false,
        channelBand: false,
        channelWidth: false,
        security: false,
        phyMode: false,
        interfaceMode: false,
        countryCode: false,
        roaming: false,
        ssidChangedAt: false,
        interfaceChangedAt: false
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

  /// Parses the built-in Wi-Fi widget.
  func parseWiFiBuiltin(from builtins: ConfigReader) throws {
    guard let wifi = try builtins.optionalSection("wifi") else { return }

    let placement = try parseBuiltinPlacement(
      reader: wifi,
      fallback: builtinWiFi.placement
    )

    let style = try parseBuiltinChromeStyle(
      reader: try wifi.section("style"),
      fallback: builtinWiFi.style
    )

    let content = try parseWiFiContent(
      reader: try wifi.section("content"),
      fallback: builtinWiFi.content
    )

    let inline = try parseWiFiInline(
      reader: try wifi.section("inline"),
      fallback: builtinWiFi.inline
    )
    let fields = try parseWiFiFields(
      reader: try wifi.section("fields"),
      fallback: builtinWiFi.fields
    )
    let popup = try parseBuiltinPopupStyle(
      reader: try wifi.section("popup"),
      fallback: builtinWiFi.popup
    )

    builtinWiFi = WiFiBuiltinConfig(
      placement: placement,
      style: style,
      content: content,
      inline: inline,
      fields: fields,
      popup: popup
    )
  }

  /// Parses Wi-Fi content settings.
  private func parseWiFiContent(
    reader: ConfigReader,
    fallback: WiFiBuiltinConfig.Content
  ) throws -> WiFiBuiltinConfig.Content {
    WiFiBuiltinConfig.Content(
      mode: try reader.enum("mode", fallback: fallback.mode),
      surface: try reader.enum("surface", fallback: fallback.surface),
      inlineSeparator: try reader.string("inline_separator", fallback: fallback.inlineSeparator),
      disconnectedText: try reader.string("disconnected_text", fallback: fallback.disconnectedText),
      deniedText: try reader.string("denied_text", fallback: fallback.deniedText),
      activeColorHex: try reader.color("active_color", fallback: fallback.activeColorHex),
      inactiveColorHex: try reader.color("inactive_color", fallback: fallback.inactiveColorHex)
    )
  }

  /// Parses Wi-Fi inline text settings.
  private func parseWiFiInline(
    reader: ConfigReader,
    fallback: BuiltinWiFiInline
  ) throws -> BuiltinWiFiInline {
    BuiltinWiFiInline(
      textColorHex: try reader.color("text_color", fallback: fallback.textColorHex)
    )
  }

  /// Parses Wi-Fi field toggles.
  private func parseWiFiFields(
    reader: ConfigReader,
    fallback: BuiltinWiFiFields
  ) throws -> BuiltinWiFiFields {
    var fields = fallback

    for metadata in BuiltinWiFiFieldCatalog.fields {
      fields[keyPath: metadata.keyPath] = try reader.bool(
        metadata.configKey,
        fallback: fields[keyPath: metadata.keyPath]
      )
    }

    return fields
  }
}
