import EasyBarShared
import Foundation

/// Render-ready Wi-Fi label, details, and icon presentation.
struct WiFiPresentation {

  /// Visual styling state for the rendered Wi-Fi content.
  enum VisualState: String {
    case connected
    case disconnected
    case denied
  }

  /// One labeled detail row shown in details mode.
  struct DetailRow {
    /// User-facing label shown for the field.
    let labelText: String
    /// User-facing value shown for the field.
    let valueText: String
  }

  /// Renderable content variants supported by the Wi-Fi widget.
  enum Content {
    case icon
    case inline(String)
    case details([DetailRow])
  }

  /// Renderable content chosen for the current snapshot and config.
  let content: Content
  /// Signal level bucket in the 0...3 range.
  let signalLevel: Int
  /// Visual state used for tinting and fallback behavior.
  let visualState: VisualState
  /// Tint used when Wi-Fi is active.
  let activeColorHex: String
  /// Tint used when Wi-Fi is inactive or unavailable.
  let inactiveColorHex: String

  /// Creates one Wi-Fi presentation from the latest network snapshot.
  init(snapshot: NetworkAgentSnapshot?, config: Config.WiFiBuiltinConfig) {
    content = Self.content(snapshot: snapshot, config: config)
    signalLevel = Self.signalLevel(snapshot: snapshot)
    visualState = Self.visualState(snapshot: snapshot)
    activeColorHex = config.activeColorHex
    inactiveColorHex = config.inactiveColorHex
  }

  /// Returns the visual signal level from RSSI in the 0...3 range.
  private static func signalLevel(snapshot: NetworkAgentSnapshot?) -> Int {
    guard
      let snapshot,
      snapshot.accessGranted,
      snapshot.ssid != nil,
      let rssi = snapshot.rssi
    else {
      return 0
    }

    switch rssi {
    case ..<(-78):
      return 1
    case ..<(-64):
      return 2
    default:
      return 3
    }
  }

  /// Resolves the Wi-Fi visual state.
  private static func visualState(snapshot: NetworkAgentSnapshot?) -> VisualState {
    guard let snapshot else { return .disconnected }
    guard snapshot.accessGranted else { return .denied }
    guard snapshot.ssid != nil else { return .disconnected }
    return .connected
  }

  /// Resolves the configured content block.
  private static func content(
    snapshot: NetworkAgentSnapshot?,
    config: Config.WiFiBuiltinConfig
  ) -> Content {
    switch config.mode {
    case .icon:
      return .icon
    case .inline:
      let text = inlineText(snapshot: snapshot, config: config)
      return text.isEmpty ? .icon : .inline(text)
    case .details:
      let rows = detailRows(snapshot: snapshot, config: config)
      return rows.isEmpty ? .icon : .details(rows)
    }
  }

  /// Resolves the configured inline field values into one joined string.
  private static func inlineText(
    snapshot: NetworkAgentSnapshot?,
    config: Config.WiFiBuiltinConfig
  ) -> String {
    detailRows(snapshot: snapshot, config: config)
      .map(\.valueText)
      .joined(separator: config.inlineSeparator)
  }

  /// Resolves one detail row list in a stable, user-facing order.
  private static func detailRows(
    snapshot: NetworkAgentSnapshot?,
    config: Config.WiFiBuiltinConfig
  ) -> [DetailRow] {
    enabledFields(config: config).compactMap { field in
      guard let value = fieldValue(for: field, snapshot: snapshot, config: config) else {
        return nil
      }

      return DetailRow(
        labelText: fieldLabel(for: field),
        valueText: value
      )
    }
  }

  /// Returns enabled fields in stable display order.
  private static func enabledFields(config: Config.WiFiBuiltinConfig) -> [NetworkAgentField] {
    BuiltinWiFiFieldCatalog.fields.compactMap { metadata in
      config.fields[keyPath: metadata.keyPath] ? metadata.agentField : nil
    }
  }

  /// Resolves one Wi-Fi field into displayable text.
  private static func fieldValue(
    for field: NetworkAgentField,
    snapshot: NetworkAgentSnapshot?,
    config: Config.WiFiBuiltinConfig
  ) -> String? {
    guard let snapshot else {
      return disconnectedFallback(for: field, config: config)
    }

    switch field {
    case .generatedAt:
      return NetworkAgentSnapshot.dateString(from: snapshot.generatedAt)
    case .locationAuthorized:
      return boolText(snapshot.accessGranted)
    case .locationPermissionState:
      return snapshot.permissionState
    default:
      break
    }

    guard snapshot.accessGranted else {
      return deniedFallback(for: field, config: config)
    }

    switch field {
    case .ssid:
      return snapshot.ssid ?? config.disconnectedText
    case .ipv4Address:
      return snapshot.ipv4Address
    case .ipv6Address:
      return snapshot.ipv6Address
    case .bssid:
      return snapshot.bssid
    case .interfaceName:
      return snapshot.interfaceName
    case .hardwareAddress:
      return snapshot.hardwareAddress
    case .power:
      return snapshot.power.map(boolText)
    case .serviceActive:
      return snapshot.serviceActive.map { $0 ? "active" : "inactive" }
    case .primaryInterfaceIsTunnel:
      return boolText(snapshot.primaryInterfaceIsTunnel)
    case .rssi:
      return snapshot.rssi.map { "\($0) dBm" }
    case .noise:
      return snapshot.noise.map { "\($0) dBm" }
    case .snr:
      return snapshot.snr.map { "\($0) dB" }
    case .linkQuality:
      return snapshot.linkQuality.map { "\($0)%" }
    case .txRate:
      return snapshot.txRate.map { "\($0) Mbps" }
    case .channel:
      return snapshot.channel.map { "ch\($0)" }
    case .channelBand:
      return snapshot.channelBand.map(humanizedRadioValue)
    case .channelWidth:
      return snapshot.channelWidth.map(humanizedRadioValue)
    case .security:
      return snapshot.security.map(humanizedIdentifier)
    case .phyMode:
      return snapshot.phyMode
    case .interfaceMode:
      return snapshot.interfaceMode.map(humanizedIdentifier)
    case .countryCode:
      return snapshot.countryCode
    case .roaming:
      return snapshot.roaming.map(boolText)
    case .ssidChangedAt:
      return snapshot.ssidChangedAt
    case .interfaceChangedAt:
      return snapshot.interfaceChangedAt
    default:
      return nil
    }
  }

  /// Returns fallback text for disconnected Wi-Fi states.
  private static func disconnectedFallback(
    for field: NetworkAgentField,
    config: Config.WiFiBuiltinConfig
  ) -> String? {
    guard field == .ssid else { return nil }
    return config.disconnectedText
  }

  /// Returns fallback text for denied Wi-Fi states.
  private static func deniedFallback(
    for field: NetworkAgentField,
    config: Config.WiFiBuiltinConfig
  ) -> String? {
    guard field == .ssid else { return nil }
    return config.deniedText
  }

  /// Returns one stable, user-facing label for the provided field.
  private static func fieldLabel(for field: NetworkAgentField) -> String {
    if let label = BuiltinWiFiFieldCatalog.displayLabel(for: field) {
      return label
    }

    switch field {
    case .generatedAt:
      return "Generated"
    case .primaryInterfaceIsTunnel:
      return "Primary Is Tunnel"
    case .locationAuthorized:
      return "Location Authorized"
    case .locationPermissionState:
      return "Location Permission"
    default:
      return humanizedFieldName(field.rawValue)
    }
  }

  /// Returns a compact boolean value for display.
  private static func boolText(_ value: Bool) -> String {
    value ? "yes" : "no"
  }

  /// Humanizes one network-agent field name for display fallback labels.
  private static func humanizedFieldName(_ value: String) -> String {
    let key = value.split(separator: ".").last.map(String.init) ?? value
    return humanizedIdentifier(key)
  }

  /// Humanizes Wi-Fi enum-like identifiers for display.
  private static func humanizedIdentifier(_ value: String) -> String {
    let parts =
      value
      .replacingOccurrences(of: "_", with: " ")
      .split(separator: " ")

    return parts.map { part in
      let raw = String(part)
      if isSecurityIdentifier(raw) {
        return raw.uppercased()
      }
      return raw.capitalized
    }.joined(separator: " ")
  }

  /// Humanizes radio values like `5ghz` and `80mhz`.
  private static func humanizedRadioValue(_ value: String) -> String {
    value
      .replacingOccurrences(of: "ghz", with: " GHz")
      .replacingOccurrences(of: "mhz", with: " MHz")
      .replacingOccurrences(of: "  ", with: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// Returns whether the identifier is a security acronym that should stay uppercase.
  private static func isSecurityIdentifier(_ value: String) -> Bool {
    return value.hasPrefix("wpa") || value.hasPrefix("wep")
  }
}
