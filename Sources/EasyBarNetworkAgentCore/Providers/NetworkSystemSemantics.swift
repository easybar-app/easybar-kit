import Darwin
import Foundation

/// Route-level facts that do not claim end-to-end Internet connectivity.
struct NetworkRouteAssessment: Equatable, Sendable {
  /// Whether SystemConfiguration reports a usable route.
  let routeReachable: Bool
  /// Whether local addressing exists while a route is unavailable.
  let routeUnavailableWithLocalAddress: Bool
  /// Confirmed captive-portal state, or nil when no portal probe ran.
  let captivePortal: Bool?

  /// Builds route semantics without inferring a captive portal from an offline LAN.
  static func make(
    routeReachable: Bool,
    hasLocalAddress: Bool,
    confirmedCaptivePortal: Bool? = nil
  ) -> NetworkRouteAssessment {
    NetworkRouteAssessment(
      routeReachable: routeReachable,
      routeUnavailableWithLocalAddress: !routeReachable && hasLocalAddress,
      captivePortal: confirmedCaptivePortal
    )
  }
}

/// Selects stable address values for the network-agent protocol.
enum NetworkAddressSelection {
  /// Prefers global IPv6, then unique-local, then scoped link-local addresses.
  static func preferredIPv6(
    from values: [String],
    scopeInterface: String?
  ) -> String? {
    let candidates = values.enumerated().compactMap { index, value -> Candidate? in
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { return nil }

      let addressPart =
        trimmed.split(separator: "%", maxSplits: 1).first.map(String.init) ?? trimmed
      var address = in6_addr()
      let parsed = addressPart.withCString { inet_pton(AF_INET6, $0, &address) }
      guard parsed == 1 else { return nil }

      let rank = withUnsafeBytes(of: &address) { bytes -> Int? in
        let octets = Array(bytes)
        let isUnspecified = octets.allSatisfy { $0 == 0 }
        let isLoopback = octets.dropLast().allSatisfy { $0 == 0 } && octets.last == 1
        guard !isUnspecified, !isLoopback, octets[0] != 0xFF else { return nil }
        if octets[0] == 0xFE && (octets[1] & 0xC0) == 0x80 { return 2 }
        if (octets[0] & 0xFE) == 0xFC { return 1 }
        return 0
      }
      guard let rank else { return nil }

      var normalized = trimmed
      if rank == 2, !trimmed.contains("%"), let scopeInterface, !scopeInterface.isEmpty {
        normalized += "%\(scopeInterface)"
      }
      return Candidate(value: normalized, rank: rank, originalIndex: index)
    }

    return candidates.min { lhs, rhs in
      if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
      return lhs.originalIndex < rhs.originalIndex
    }?.value
  }

  /// Stores candidate data.
  private struct Candidate {
    /// The value for this candidate.
    let value: String
    /// The rank for this candidate.
    let rank: Int
    /// The original index for this candidate.
    let originalIndex: Int
  }
}

/// Enumerates active interfaces independently of dynamic-store service dictionaries.
enum NetworkInterfaceDiscovery {
  /// Returns stable tunnel names from any interface inventory.
  static func tunnelInterfaces(from names: [String]) -> [String] {
    Array(Set(names.filter(isTunnelInterface))).sorted()
  }

  /// Returns whether one interface name represents a supported tunnel family.
  static func isTunnelInterface(_ name: String) -> Bool {
    name.hasPrefix("utun")
      || name.hasPrefix("ppp")
      || name.hasPrefix("ipsec")
      || name.hasPrefix("tap")
      || name.hasPrefix("tun")
  }

  /// Returns active, non-loopback interface names in deterministic order.
  static func activeInterfaceNames() -> [String] {
    var firstAddress: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&firstAddress) == 0, let firstAddress else { return [] }
    defer { freeifaddrs(firstAddress) }

    var names = Set<String>()
    var cursor: UnsafeMutablePointer<ifaddrs>? = firstAddress
    while let pointer = cursor {
      let interface = pointer.pointee
      let flags = interface.ifa_flags
      if flags & UInt32(IFF_UP) != 0, flags & UInt32(IFF_LOOPBACK) == 0,
        let rawName = interface.ifa_name
      {
        let name = String(cString: rawName).trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
          names.insert(name)
        }
      }
      cursor = interface.ifa_next
    }

    return names.sorted()
  }
}
