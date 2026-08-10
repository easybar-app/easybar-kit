import Foundation

/// Stable field keys that clients can request from the network agent.
public enum NetworkAgentField: String, Codable, CaseIterable, Sendable {
  case generatedAt = "network.generated_at"
  case ssid = "wifi.ssid"
  case bssid = "wifi.bssid"
  case interfaceName = "wifi.interface"
  case hardwareAddress = "wifi.hardware_address"
  case power = "wifi.power"
  case serviceActive = "wifi.service_active"
  case primaryInterfaceIsTunnel = "network.primary_interface_is_tunnel"
  case rssi = "wifi.rssi"
  case noise = "wifi.noise"
  case snr = "wifi.snr"
  case linkQuality = "wifi.link_quality"
  case txRate = "wifi.tx_rate"
  case channel = "wifi.channel"
  case channelBand = "wifi.channel_band"
  case channelWidth = "wifi.channel_width"
  case security = "wifi.security"
  case phyMode = "wifi.phy_mode"
  case interfaceMode = "wifi.interface_mode"
  case countryCode = "wifi.country_code"
  case roaming = "wifi.roaming"
  case ssidChangedAt = "wifi.ssid_changed_at"
  case interfaceChangedAt = "wifi.interface_changed_at"
  case primaryInterface = "network.primary_interface"
  case activeTunnelInterface = "network.active_tunnel_interface"
  case activeTunnelInterfaces = "network.active_tunnel_interfaces"
  case ipv4Address = "network.ipv4_address"
  case ipv6Address = "network.ipv6_address"
  case defaultGateway = "network.default_gateway"
  case dnsServers = "network.dns_servers"
  case routeReachable = "network.route_reachable"
  case routeUnavailableWithLocalAddress = "network.route_unavailable_with_local_address"
  case captivePortal = "network.captive_portal"
  case locationAuthorized = "auth.location_authorized"
  case locationPermissionState = "auth.location_permission_state"
}

/// Stable field namespaces supported by the network agent.
public enum NetworkAgentFieldNamespace: String, Codable, CaseIterable, Sendable {
  case wifi
  case network
  case auth

  /// Prefix shared by every field in this namespace.
  public var fieldPrefix: String {
    return rawValue + "."
  }

  /// Returns whether the namespace contains the provided field.
  public func contains(_ field: NetworkAgentField) -> Bool {
    return field.rawValue.hasPrefix(fieldPrefix)
  }
}

/// Describes one shared network-agent field.
public struct NetworkAgentFieldSpec: Sendable {
  /// Field key used on the wire.
  public let field: NetworkAgentField
  /// Short help text for humans.
  public let help: String
  /// Whether the field requires location authorization.
  public let requiresLocationAuthorization: Bool

  /// Creates one network-agent field spec.
  public init(
    field: NetworkAgentField,
    help: String,
    requiresLocationAuthorization: Bool = false
  ) {
    self.field = field
    self.help = help
    self.requiresLocationAuthorization = requiresLocationAuthorization
  }
}

/// Describes one shared network-agent namespace selector.
public struct NetworkAgentFieldNamespaceSpec: Sendable {
  /// Namespace key accepted by clients.
  public let namespace: NetworkAgentFieldNamespace
  /// Short help text for humans.
  public let help: String

  /// Creates one shared network-agent namespace selector.
  public init(namespace: NetworkAgentFieldNamespace, help: String) {
    self.namespace = namespace
    self.help = help
  }
}

/// Ordered network-agent field metadata shared by clients and the agent.
public let networkAgentFieldRegistry: [NetworkAgentFieldSpec] = [
  .init(field: .ssid, help: "Current Wi-Fi network name", requiresLocationAuthorization: true),
  .init(field: .bssid, help: "Current access point BSSID", requiresLocationAuthorization: true),
  .init(field: .interfaceName, help: "Wi-Fi interface name", requiresLocationAuthorization: true),
  .init(
    field: .hardwareAddress,
    help: "Wi-Fi hardware MAC address",
    requiresLocationAuthorization: true
  ),
  .init(field: .power, help: "Wi-Fi power state", requiresLocationAuthorization: true),
  .init(
    field: .serviceActive,
    help: "CoreWLAN service availability",
    requiresLocationAuthorization: true
  ),
  .init(field: .rssi, help: "Received signal strength", requiresLocationAuthorization: true),
  .init(field: .noise, help: "Noise floor", requiresLocationAuthorization: true),
  .init(field: .snr, help: "Signal-to-noise ratio", requiresLocationAuthorization: true),
  .init(
    field: .linkQuality,
    help: "Derived link quality percent",
    requiresLocationAuthorization: true
  ),
  .init(field: .txRate, help: "Transmit rate in Mbps", requiresLocationAuthorization: true),
  .init(field: .channel, help: "Current Wi-Fi channel", requiresLocationAuthorization: true),
  .init(field: .channelBand, help: "Channel band label", requiresLocationAuthorization: true),
  .init(field: .channelWidth, help: "Channel width label", requiresLocationAuthorization: true),
  .init(field: .security, help: "Current security mode", requiresLocationAuthorization: true),
  .init(field: .phyMode, help: "PHY mode label", requiresLocationAuthorization: true),
  .init(field: .interfaceMode, help: "Interface mode label", requiresLocationAuthorization: true),
  .init(field: .countryCode, help: "Current country code", requiresLocationAuthorization: true),
  .init(field: .roaming, help: "Roaming state", requiresLocationAuthorization: true),
  .init(
    field: .ssidChangedAt,
    help: "Last SSID change time",
    requiresLocationAuthorization: true
  ),
  .init(
    field: .interfaceChangedAt,
    help: "Last interface change time",
    requiresLocationAuthorization: true
  ),
  .init(field: .primaryInterface, help: "Primary network interface"),
  .init(field: .activeTunnelInterface, help: "First active tunnel interface"),
  .init(field: .activeTunnelInterfaces, help: "All active tunnel interfaces"),
  .init(field: .primaryInterfaceIsTunnel, help: "Whether the primary interface is a tunnel"),
  .init(field: .ipv4Address, help: "Primary IPv4 address"),
  .init(field: .ipv6Address, help: "Primary IPv6 address"),
  .init(field: .defaultGateway, help: "Default gateway address"),
  .init(field: .dnsServers, help: "Configured DNS servers"),
  .init(field: .routeReachable, help: "Whether SystemConfiguration reports a usable route"),
  .init(
    field: .routeUnavailableWithLocalAddress,
    help: "Whether a local address exists while no usable route is reported"
  ),
  .init(
    field: .captivePortal,
    help: "Confirmed captive-portal state when a probe is available"
  ),
  .init(field: .locationAuthorized, help: "Location authorization state"),
  .init(field: .locationPermissionState, help: "Location permission label"),
  .init(field: .generatedAt, help: "Snapshot generation time"),
]

/// Ordered namespace selectors shared by clients.
public let networkAgentFieldNamespaceRegistry: [NetworkAgentFieldNamespaceSpec] = [
  .init(namespace: .wifi, help: "Expand to every Wi-Fi field"),
  .init(namespace: .network, help: "Expand to every network field"),
  .init(namespace: .auth, help: "Expand to every authorization field"),
]

/// One selector-expansion error shared by clients.
public enum NetworkAgentFieldSelectorError: LocalizedError, Equatable, Sendable {
  case unknownFieldOrSelector(String)

  /// Returns the localized selector error message.
  public var errorDescription: String? {
    switch self {
    case .unknownFieldOrSelector(let value):
      return "unknown field or selector: \(value)"
    }
  }
}

/// Network-agent field metadata keyed by field.
public let networkAgentFieldSpecsByField = Dictionary(
  uniqueKeysWithValues: networkAgentFieldRegistry.map { ($0.field, $0) }
)

private let networkAgentFieldsInRegistryOrder = networkAgentFieldRegistry.map(\.field)
private let networkAgentFieldsByRawValue = Dictionary(
  uniqueKeysWithValues: networkAgentFieldsInRegistryOrder.map { ($0.rawValue, $0) }
)

/// Returns the registry descriptor for one network-agent field.
public func networkAgentFieldSpec(for field: NetworkAgentField) -> NetworkAgentFieldSpec? {
  networkAgentFieldSpecsByField[field]
}

/// Returns whether one network-agent field requires location authorization.
public func networkAgentFieldRequiresLocationAuthorization(_ field: NetworkAgentField) -> Bool {
  networkAgentFieldSpec(for: field)?.requiresLocationAuthorization ?? false
}

/// Expands field names and shared selectors into concrete fields.
public func expandNetworkAgentFieldSelectors(_ selectors: [String]) throws -> [NetworkAgentField] {
  var expanded: [NetworkAgentField] = []
  var seen: Set<NetworkAgentField> = []

  for selector in selectors.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }).filter({
    !$0.isEmpty
  }) {
    for field in try expandNetworkAgentFieldSelector(selector) {
      if seen.insert(field).inserted {
        expanded.append(field)
      }
    }
  }

  return expanded
}

/// Expands one field name or selector into concrete fields.
public func expandNetworkAgentFieldSelector(_ selector: String) throws -> [NetworkAgentField] {
  if selector == "all" {
    return networkAgentFieldsInRegistryOrder
  }

  if let field = networkAgentFieldsByRawValue[selector] {
    return [field]
  }

  guard let namespace = networkAgentFieldNamespace(for: selector) else {
    throw NetworkAgentFieldSelectorError.unknownFieldOrSelector(selector)
  }

  return networkAgentFieldsInRegistryOrder.filter(namespace.contains)
}

/// Handles network agent field namespace.
private func networkAgentFieldNamespace(for selector: String) -> NetworkAgentFieldNamespace? {
  if let namespace = NetworkAgentFieldNamespace(rawValue: selector) {
    return namespace
  }

  if selector.hasSuffix("."),
    let namespace = NetworkAgentFieldNamespace(rawValue: String(selector.dropLast()))
  {
    return namespace
  }

  if selector.hasSuffix(".*"),
    let namespace = NetworkAgentFieldNamespace(rawValue: String(selector.dropLast(2)))
  {
    return namespace
  }

  return nil
}
