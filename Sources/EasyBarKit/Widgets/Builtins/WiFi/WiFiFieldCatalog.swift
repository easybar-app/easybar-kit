import EasyBarShared

/// Describes one user-configurable native Wi-Fi field.
struct WiFiFieldDescriptor {
  /// Config key under `[builtins.wifi.fields]`.
  let configKey: String
  /// Boolean toggle in `Config.BuiltinWiFiFields`.
  let keyPath: WritableKeyPath<Config.BuiltinWiFiFields, Bool>
  /// Network-agent field requested and rendered for this toggle.
  let agentField: NetworkAgentField
  /// User-facing label used in details mode.
  let displayLabel: String
}

/// Stable field catalog shared by Wi-Fi config parsing and presentation.
enum BuiltinWiFiFieldCatalog {
  /// Fields in the order they should be requested and displayed by the widget.
  nonisolated(unsafe) static let fields: [WiFiFieldDescriptor] = [
    .init(
      configKey: "ssid",
      keyPath: \.ssid,
      agentField: .ssid,
      displayLabel: "SSID"
    ),
    .init(
      configKey: "ipv4_address",
      keyPath: \.ipv4Address,
      agentField: .ipv4Address,
      displayLabel: "IPv4 Address"
    ),
    .init(
      configKey: "ipv6_address",
      keyPath: \.ipv6Address,
      agentField: .ipv6Address,
      displayLabel: "IPv6 Address"
    ),
    .init(
      configKey: "rssi",
      keyPath: \.rssi,
      agentField: .rssi,
      displayLabel: "Signal"
    ),
    .init(
      configKey: "link_quality",
      keyPath: \.linkQuality,
      agentField: .linkQuality,
      displayLabel: "Link Quality"
    ),
    .init(
      configKey: "tx_rate",
      keyPath: \.txRate,
      agentField: .txRate,
      displayLabel: "Rate"
    ),
    .init(
      configKey: "channel",
      keyPath: \.channel,
      agentField: .channel,
      displayLabel: "Channel"
    ),
    .init(
      configKey: "channel_band",
      keyPath: \.channelBand,
      agentField: .channelBand,
      displayLabel: "Band"
    ),
    .init(
      configKey: "channel_width",
      keyPath: \.channelWidth,
      agentField: .channelWidth,
      displayLabel: "Width"
    ),
    .init(
      configKey: "security",
      keyPath: \.security,
      agentField: .security,
      displayLabel: "Security"
    ),
    .init(
      configKey: "phy_mode",
      keyPath: \.phyMode,
      agentField: .phyMode,
      displayLabel: "PHY"
    ),
    .init(
      configKey: "interface",
      keyPath: \.interfaceName,
      agentField: .interfaceName,
      displayLabel: "Interface"
    ),
    .init(
      configKey: "interface_mode",
      keyPath: \.interfaceMode,
      agentField: .interfaceMode,
      displayLabel: "Mode"
    ),
    .init(
      configKey: "bssid",
      keyPath: \.bssid,
      agentField: .bssid,
      displayLabel: "BSSID"
    ),
    .init(
      configKey: "hardware_address",
      keyPath: \.hardwareAddress,
      agentField: .hardwareAddress,
      displayLabel: "MAC"
    ),
    .init(
      configKey: "power",
      keyPath: \.power,
      agentField: .power,
      displayLabel: "Power"
    ),
    .init(
      configKey: "service_active",
      keyPath: \.serviceActive,
      agentField: .serviceActive,
      displayLabel: "Service"
    ),
    .init(
      configKey: "noise",
      keyPath: \.noise,
      agentField: .noise,
      displayLabel: "Noise"
    ),
    .init(
      configKey: "snr",
      keyPath: \.snr,
      agentField: .snr,
      displayLabel: "SNR"
    ),
    .init(
      configKey: "country_code",
      keyPath: \.countryCode,
      agentField: .countryCode,
      displayLabel: "Country"
    ),
    .init(
      configKey: "roaming",
      keyPath: \.roaming,
      agentField: .roaming,
      displayLabel: "Roaming"
    ),
    .init(
      configKey: "ssid_changed_at",
      keyPath: \.ssidChangedAt,
      agentField: .ssidChangedAt,
      displayLabel: "SSID Changed"
    ),
    .init(
      configKey: "interface_changed_at",
      keyPath: \.interfaceChangedAt,
      agentField: .interfaceChangedAt,
      displayLabel: "Interface Changed"
    ),
  ]

  /// Returns the configured display label for one network-agent field.
  static func displayLabel(for agentField: NetworkAgentField) -> String? {
    fields.first { $0.agentField == agentField }?.displayLabel
  }
}
