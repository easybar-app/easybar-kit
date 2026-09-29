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
    /// The text color hex for this builtin Wi-Fi inline.
    var textColorHex: String
  }

  /// Wi-Fi detail field toggles.
  struct BuiltinWiFiFields {
    /// Whether the SSID option is enabled for this builtin Wi-Fi fields.
    var ssid: Bool
    /// Whether the IPv4 address option is enabled for this builtin Wi-Fi fields.
    var ipv4Address: Bool
    /// Whether the IPv6 address option is enabled for this builtin Wi-Fi fields.
    var ipv6Address: Bool
    /// Whether the BSSID option is enabled for this builtin Wi-Fi fields.
    var bssid: Bool
    /// Whether the interface name option is enabled for this builtin Wi-Fi fields.
    var interfaceName: Bool
    /// Whether the hardware address option is enabled for this builtin Wi-Fi fields.
    var hardwareAddress: Bool
    /// Whether the power option is enabled for this builtin Wi-Fi fields.
    var power: Bool
    /// Whether the service active option is enabled for this builtin Wi-Fi fields.
    var serviceActive: Bool
    /// Whether the RSSI option is enabled for this builtin Wi-Fi fields.
    var rssi: Bool
    /// Whether the noise option is enabled for this builtin Wi-Fi fields.
    var noise: Bool
    /// Whether the SNR option is enabled for this builtin Wi-Fi fields.
    var snr: Bool
    /// Whether the link quality option is enabled for this builtin Wi-Fi fields.
    var linkQuality: Bool
    /// Whether the transmit rate option is enabled for this builtin Wi-Fi fields.
    var txRate: Bool
    /// Whether the channel option is enabled for this builtin Wi-Fi fields.
    var channel: Bool
    /// Whether the channel band option is enabled for this builtin Wi-Fi fields.
    var channelBand: Bool
    /// Whether the channel width option is enabled for this builtin Wi-Fi fields.
    var channelWidth: Bool
    /// Whether the security option is enabled for this builtin Wi-Fi fields.
    var security: Bool
    /// Whether the phy mode option is enabled for this builtin Wi-Fi fields.
    var phyMode: Bool
    /// Whether the interface mode option is enabled for this builtin Wi-Fi fields.
    var interfaceMode: Bool
    /// Whether the country code option is enabled for this builtin Wi-Fi fields.
    var countryCode: Bool
    /// Whether the roaming option is enabled for this builtin Wi-Fi fields.
    var roaming: Bool
    /// Whether the SSID changed at option is enabled for this builtin Wi-Fi fields.
    var ssidChangedAt: Bool
    /// Whether the interface changed at option is enabled for this builtin Wi-Fi fields.
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
      /// The mode for this content.
      var mode: BuiltinWiFiContentMode
      /// The surface for this content.
      var surface: BuiltinWiFiContentSurface
      /// The inline separator for this content.
      var inlineSeparator: String
      /// The disconnected text for this content.
      var disconnectedText: String
      /// The denied text for this content.
      var deniedText: String
      /// The active color hex for this content.
      var activeColorHex: String
      /// The inactive color hex for this content.
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

    /// Whether this Wi-Fi builtin config is enabled.
    var enabled: Bool {
      get { placement.enabled }
      set { placement.enabled = newValue }
    }

    /// The position for this Wi-Fi builtin config.
    var position: WidgetPosition {
      get { placement.position }
      set { placement.position = newValue }
    }

    /// The order for this Wi-Fi builtin config.
    var order: Int {
      get { placement.order }
      set { placement.order = newValue }
    }

    /// The mode for this Wi-Fi builtin config.
    var mode: BuiltinWiFiContentMode {
      get { content.mode }
      set { content.mode = newValue }
    }

    /// The surface for this Wi-Fi builtin config.
    var surface: BuiltinWiFiContentSurface {
      get { content.surface }
      set { content.surface = newValue }
    }

    /// The inline separator for this Wi-Fi builtin config.
    var inlineSeparator: String {
      get { content.inlineSeparator }
      set { content.inlineSeparator = newValue }
    }

    /// The disconnected text for this Wi-Fi builtin config.
    var disconnectedText: String {
      get { content.disconnectedText }
      set { content.disconnectedText = newValue }
    }

    /// The denied text for this Wi-Fi builtin config.
    var deniedText: String {
      get { content.deniedText }
      set { content.deniedText = newValue }
    }

    /// The active color hex for this Wi-Fi builtin config.
    var activeColorHex: String {
      get { content.activeColorHex }
      set { content.activeColorHex = newValue }
    }

    /// The inactive color hex for this Wi-Fi builtin config.
    var inactiveColorHex: String {
      get { content.inactiveColorHex }
      set { content.inactiveColorHex = newValue }
    }

    /// The inline text color hex for this Wi-Fi builtin config.
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
