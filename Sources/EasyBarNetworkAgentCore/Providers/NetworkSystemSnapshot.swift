import Foundation

/// Normalized SystemConfiguration network state.
struct NetworkSystemSnapshot: Equatable, Sendable {
  /// Empty fallback snapshot used when system state cannot be read.
  static let empty = NetworkSystemSnapshot(
    primaryInterface: nil,
    activeTunnelInterface: nil,
    activeTunnelInterfaces: [],
    primaryInterfaceIsTunnel: false,
    ipv4Address: nil,
    ipv6Address: nil,
    defaultGateway: nil,
    dnsServers: [],
    routeReachable: false,
    routeUnavailableWithLocalAddress: false,
    captivePortal: nil
  )

  /// Primary network interface name.
  let primaryInterface: String?
  /// First active tunnel interface.
  let activeTunnelInterface: String?
  /// Active tunnel interface names.
  let activeTunnelInterfaces: [String]
  /// Whether the primary interface is a tunnel.
  let primaryInterfaceIsTunnel: Bool
  /// Primary IPv4 address.
  let ipv4Address: String?
  /// Preferred primary IPv6 address.
  let ipv6Address: String?
  /// Default gateway address.
  let defaultGateway: String?
  /// Configured DNS servers.
  let dnsServers: [String]
  /// Whether SystemConfiguration reports a usable route.
  let routeReachable: Bool
  /// Whether local addressing exists while a route is unavailable.
  let routeUnavailableWithLocalAddress: Bool
  /// Confirmed captive-portal state, or nil when no probe ran.
  let captivePortal: Bool?
}
