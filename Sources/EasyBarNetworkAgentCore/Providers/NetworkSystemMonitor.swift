@preconcurrency import CoreFoundation
import Darwin
import EasyBarShared
import Foundation
import SystemConfiguration

/// Watches SystemConfiguration network state.
@MainActor
final class NetworkSystemMonitor {
  /// Dynamic store keys that should trigger refreshes.
  nonisolated(unsafe) private static let watchedNetworkPatterns: [CFString] = [
    "State:/Network/Global/IPv4" as CFString,
    "State:/Network/Global/IPv6" as CFString,
    "State:/Network/Global/DNS" as CFString,
    "State:/Network/Service/.*/IPv4" as CFString,
    "State:/Network/Service/.*/IPv6" as CFString,
    "State:/Network/Interface/.*/Link" as CFString,
    "State:/Network/Interface/.*/IPv4" as CFString,
    "State:/Network/Interface/.*/IPv6" as CFString,
  ]

  private let componentName: String
  private let logger: ProcessLogger
  private let interfaceNames: () -> [String]
  private let routeReachable: () -> Bool
  private var onChange: (() -> Void)?
  private var store: SCDynamicStore?
  private var storeSource: CFRunLoopSource?

  /// Creates one network system monitor that logs through the provided logger.
  init(
    componentName: String,
    logger: ProcessLogger,
    interfaceNames: @escaping () -> [String] = NetworkInterfaceDiscovery.activeInterfaceNames,
    routeReachable: @escaping () -> Bool = NetworkSystemMonitor.currentRouteReachability
  ) {
    self.componentName = componentName
    self.logger = logger
    self.interfaceNames = interfaceNames
    self.routeReachable = routeReachable
  }

  /// Starts listening for primary network interface changes.
  func start(onChange: @escaping () -> Void) {
    self.onChange = onChange

    guard store == nil, storeSource == nil else {
      return
    }

    var context = SCDynamicStoreContext(
      version: 0,
      info: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
      retain: nil,
      release: nil,
      copyDescription: nil
    )

    guard
      let store = SCDynamicStoreCreate(
        nil,
        componentName as CFString,
        { _, _, info in
          guard let info else { return }
          let monitor = Unmanaged<NetworkSystemMonitor>.fromOpaque(info).takeUnretainedValue()
          Task { @MainActor in
            monitor.handleNetworkStoreChange()
          }
        },
        &context
      )
    else {
      logger.warn("failed to create \(componentName) dynamic store")
      return
    }

    guard SCDynamicStoreSetNotificationKeys(store, nil, Self.watchedNetworkPatterns as CFArray)
    else {
      logger.warn("failed to register \(componentName) dynamic store notification keys")
      return
    }

    guard let source = SCDynamicStoreCreateRunLoopSource(nil, store, 0) else {
      logger.warn("failed to create \(componentName) dynamic store source")
      return
    }

    self.store = store
    storeSource = source

    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    logger.info("\(componentName) subscribed network_change")
  }

  /// Stops network monitoring.
  func stop() {
    if let storeSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), storeSource, .commonModes)
    }

    storeSource = nil
    store = nil
    onChange = nil
  }

  /// Returns the current normalized network state.
  func currentState() -> NetworkSystemSnapshot {
    guard let store else {
      return .empty
    }

    guard
      let raw = SCDynamicStoreCopyMultiple(store, nil, Self.watchedNetworkPatterns as CFArray)
        as? [String: Any]
    else {
      return .empty
    }

    var allInterfaces: [String] = []
    var seenInterfaces = Set<String>()

    /// Appends interface.
    func appendInterface(_ name: String) {
      guard seenInterfaces.insert(name).inserted else { return }
      allInterfaces.append(name)
    }

    for name in interfaceNames() {
      appendInterface(name)
    }

    let globalIPv4 = raw["State:/Network/Global/IPv4"] as? [String: Any]
    let globalIPv6 = raw["State:/Network/Global/IPv6"] as? [String: Any]
    let globalDNS = raw["State:/Network/Global/DNS"] as? [String: Any]

    let primaryInterface =
      normalized(globalIPv4?["PrimaryInterface"] as? String)
      ?? normalized(globalIPv6?["PrimaryInterface"] as? String)

    let primaryServiceID =
      normalized(globalIPv4?["PrimaryService"] as? String)
      ?? normalized(globalIPv6?["PrimaryService"] as? String)

    if let primaryInterface {
      appendInterface(primaryInterface)
    }

    for (key, value) in raw {
      guard key.hasPrefix("State:/Network/Service/") else { continue }
      guard key.hasSuffix("/IPv4") || key.hasSuffix("/IPv6") else { continue }
      guard
        let payload = value as? [String: Any],
        let interfaceName = normalized(payload["InterfaceName"] as? String)
      else {
        continue
      }

      appendInterface(interfaceName)
    }

    let tunnelInterfaces = NetworkInterfaceDiscovery.tunnelInterfaces(from: allInterfaces)
    let primaryInterfaceIsTunnel =
      primaryInterface.map(NetworkInterfaceDiscovery.isTunnelInterface) ?? false
    let activeTunnelInterface = primaryInterfaceIsTunnel ? primaryInterface : tunnelInterfaces.first
    let primaryIPv4 = primaryServiceID.flatMap {
      raw["State:/Network/Service/\($0)/IPv4"] as? [String: Any]
    }
    let primaryIPv6 = primaryServiceID.flatMap {
      raw["State:/Network/Service/\($0)/IPv6"] as? [String: Any]
    }

    let ipv4Address = firstString(in: primaryIPv4?["Addresses"])
    let ipv6Address = NetworkAddressSelection.preferredIPv6(
      from: stringArray(in: primaryIPv6?["Addresses"]),
      scopeInterface: primaryInterface
    )
    let defaultGateway =
      normalized(globalIPv4?["Router"] as? String)
      ?? normalized(primaryIPv4?["Router"] as? String)
    let dnsServers = stringArray(in: globalDNS?["ServerAddresses"])
    let assessment = NetworkRouteAssessment.make(
      routeReachable: routeReachable(),
      hasLocalAddress: ipv4Address != nil || ipv6Address != nil
    )

    return NetworkSystemSnapshot(
      primaryInterface: primaryInterface,
      activeTunnelInterface: activeTunnelInterface,
      activeTunnelInterfaces: tunnelInterfaces,
      primaryInterfaceIsTunnel: primaryInterfaceIsTunnel,
      ipv4Address: ipv4Address,
      ipv6Address: ipv6Address,
      defaultGateway: defaultGateway,
      dnsServers: dnsServers,
      routeReachable: assessment.routeReachable,
      routeUnavailableWithLocalAddress: assessment.routeUnavailableWithLocalAddress,
      captivePortal: assessment.captivePortal
    )
  }

  /// Handles one dynamic store change callback.
  private func handleNetworkStoreChange() {
    logger.info("\(componentName) dynamic store changed")
    onChange?()
  }

  /// Returns whether SystemConfiguration reports a usable route.
  private nonisolated static func currentRouteReachability() -> Bool {
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)

    let reachability = withUnsafePointer(to: &address) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
        SCNetworkReachabilityCreateWithAddress(nil, socketAddress)
      }
    }
    guard let reachability else { return false }

    var flags = SCNetworkReachabilityFlags()
    guard SCNetworkReachabilityGetFlags(reachability, &flags) else {
      return false
    }

    return flags.contains(.reachable) && !flags.contains(.connectionRequired)
  }

  /// Returns the first trimmed string from an array-like value.
  private func firstString(in value: Any?) -> String? {
    stringArray(in: value).first
  }

  /// Returns a cleaned string array from an array-like value.
  private func stringArray(in value: Any?) -> [String] {
    guard let values = value as? [String] else { return [] }
    return values.compactMap(normalized)
  }

  /// Trims one optional string and drops empty values.
  private func normalized(_ value: String?) -> String? {
    guard let value else { return nil }

    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
