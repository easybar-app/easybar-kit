import EasyBarShared
import Foundation

/// Injectable monitor operations used by the main-actor snapshot provider.
@MainActor
struct NetworkSnapshotProviderDependencies {
  let startAuthorization: @MainActor (@escaping () -> Void) -> Void
  let stopAuthorization: @MainActor () -> Void
  let authorizationSnapshot: @MainActor () -> NetworkAuthorizationSnapshot
  let startWiFi: @MainActor (@escaping () -> Void) -> Void
  let stopWiFi: @MainActor () -> Void
  let refreshWiFi: @MainActor (Date) -> Void
  let currentWiFi: @MainActor () -> NetworkWiFiSnapshot
  let startSystem: @MainActor (@escaping () -> Void) -> Void
  let stopSystem: @MainActor () -> Void
  let currentSystem: @MainActor () -> NetworkSystemSnapshot
}

/// Provides authorization-aware network snapshots.
@MainActor
public final class NetworkSnapshotProvider {
  /// Immutable values used while resolving requested field values.
  private struct FieldResolutionContext {
    let now: Date
    let authorization: NetworkAuthorizationSnapshot
    let wifi: NetworkWiFiSnapshot
    let network: NetworkSystemSnapshot
  }

  private let componentName: String
  private let refreshIntervalSeconds: TimeInterval
  private let logger: ProcessLogger
  private let dependencies: NetworkSnapshotProviderDependencies

  private var onChange: (() -> Void)?
  private var refreshTask: Task<Void, Never>?
  private var isRunning = false

  /// Builds the network snapshot provider with one refresh interval.
  public convenience init(
    componentName: String,
    refreshIntervalSeconds: TimeInterval,
    logger: ProcessLogger,
    promptPresenter: NetworkAuthorizationPromptPresenter? = nil
  ) {
    let authorizer = NetworkLocationAuthorizationController(
      componentName: componentName,
      logger: logger.child("authorization"),
      promptPresenter: promptPresenter
    )
    let wifiMonitor = NetworkWiFiMonitor(
      componentName: componentName,
      logger: logger.child("wifi_monitor")
    )
    let systemMonitor = NetworkSystemMonitor(
      componentName: componentName,
      logger: logger.child("system_monitor")
    )

    self.init(
      componentName: componentName,
      refreshIntervalSeconds: refreshIntervalSeconds,
      logger: logger,
      dependencies: NetworkSnapshotProviderDependencies(
        startAuthorization: authorizer.start(onChange:),
        stopAuthorization: authorizer.stop,
        authorizationSnapshot: authorizer.snapshot,
        startWiFi: wifiMonitor.start(onChange:),
        stopWiFi: wifiMonitor.stop,
        refreshWiFi: wifiMonitor.refreshState(now:),
        currentWiFi: wifiMonitor.currentState,
        startSystem: systemMonitor.start(onChange:),
        stopSystem: systemMonitor.stop,
        currentSystem: systemMonitor.currentState
      )
    )
  }

  /// Builds a provider from injected monitor operations for regression testing.
  init(
    componentName: String,
    refreshIntervalSeconds: TimeInterval,
    logger: ProcessLogger,
    dependencies: NetworkSnapshotProviderDependencies
  ) {
    self.componentName = componentName
    self.refreshIntervalSeconds = refreshIntervalSeconds
    self.logger = logger
    self.dependencies = dependencies
  }

  /// Starts permission, Wi-Fi, and network monitoring once.
  public func start(onChange: @escaping () -> Void) {
    self.onChange = onChange

    guard !isRunning else {
      onChange()
      return
    }
    isRunning = true

    let notify: () -> Void = { [weak self] in
      Task { @MainActor [weak self] in
        guard let self, self.isRunning else { return }
        self.onChange?()
      }
    }

    dependencies.startAuthorization { [weak self] in
      Task { @MainActor [weak self] in
        guard let self, self.isRunning else { return }
        self.dependencies.refreshWiFi(Date())
        self.onChange?()
      }
    }
    dependencies.startWiFi(notify)
    dependencies.startSystem(notify)

    logger.info(
      "\(componentName) refresh",
      .field("interval_seconds", refreshIntervalSeconds)
    )

    if usesPeriodicRefresh {
      refreshTask = Task { @MainActor [weak self] in
        while let self, self.isRunning, !Task.isCancelled {
          do {
            try await Task.sleep(for: .seconds(self.refreshIntervalSeconds))
          } catch {
            return
          }

          guard self.isRunning, !Task.isCancelled else { return }
          self.dependencies.refreshWiFi(Date())
          self.onChange?()
        }
      }
    }

    onChange()
  }

  private var usesPeriodicRefresh: Bool {
    refreshIntervalSeconds.isFinite && refreshIntervalSeconds > 0
  }

  /// Stops delayed refreshes and all active monitoring.
  public func stop() {
    guard isRunning else {
      onChange = nil
      return
    }
    isRunning = false

    refreshTask?.cancel()
    refreshTask = nil

    dependencies.stopAuthorization()
    dependencies.stopWiFi()
    dependencies.stopSystem()

    onChange = nil
  }

  /// Builds one network snapshot from a consistent current-state context.
  public func snapshot() -> NetworkAgentSnapshot {
    let context = fieldResolutionContext()

    logger.debug(
      "\(componentName) snapshot",
      .field("access_granted", context.authorization.isAuthorized),
      .field("permission_state", context.authorization.permissionState),
      .field("ssid", context.wifi.ssid ?? "<none>"),
      .field("interface", context.wifi.interfaceName ?? "<none>"),
      .field("ipv4_address", context.network.ipv4Address ?? "<none>"),
      .field("ipv6_address", context.network.ipv6Address ?? "<none>"),
      .field("rssi", context.wifi.rssi.map(String.init) ?? "<none>"),
      .field("primary_is_tunnel", context.network.primaryInterfaceIsTunnel),
    )

    return NetworkAgentSnapshot(
      accessGranted: context.authorization.isAuthorized,
      permissionState: context.authorization.permissionState,
      generatedAt: context.now,
      ssid: context.wifi.ssid,
      ipv4Address: context.network.ipv4Address,
      ipv6Address: context.network.ipv6Address,
      bssid: context.wifi.bssid,
      interfaceName: context.wifi.interfaceName,
      hardwareAddress: context.wifi.hardwareAddress,
      power: context.wifi.power,
      serviceActive: context.wifi.serviceActive,
      primaryInterfaceIsTunnel: context.network.primaryInterfaceIsTunnel,
      rssi: context.wifi.rssi,
      noise: context.wifi.noise,
      snr: context.wifi.snr,
      linkQuality: context.wifi.linkQuality,
      txRate: context.wifi.txRate,
      channel: context.wifi.channel,
      channelBand: context.wifi.channelBand,
      channelWidth: context.wifi.channelWidth,
      security: context.wifi.security,
      phyMode: context.wifi.phyMode,
      interfaceMode: context.wifi.interfaceMode,
      countryCode: context.wifi.countryCode,
      roaming: context.wifi.roaming,
      ssidChangedAt: context.wifi.ssidChangedAt,
      interfaceChangedAt: context.wifi.interfaceChangedAt
    )
  }

  /// Returns requested values and explicit availability for every requested field.
  public func responseFields(
    for fields: [NetworkAgentField],
    allowUnauthorizedFieldsWithoutLocation: Bool
  ) -> (
    values: [String: NetworkAgentFieldValue]?,
    statuses: [String: NetworkAgentFieldStatus]?,
    errorCode: NetworkAgentErrorCode?
  ) {
    let context = fieldResolutionContext()
    guard context.authorization.isAuthorized else {
      return unauthorizedFieldResponse(
        for: fields,
        context: context,
        allowUnauthorizedFieldsWithoutLocation: allowUnauthorizedFieldsWithoutLocation
      )
    }

    let response = resolvedFieldResponse(for: fields, context: context)
    return (response.values, response.statuses, nil)
  }

  /// Returns values and availability statuses for one immutable context.
  private func resolvedFieldResponse(
    for fields: [NetworkAgentField],
    context: FieldResolutionContext
  ) -> (
    values: [String: NetworkAgentFieldValue],
    statuses: [String: NetworkAgentFieldStatus]
  ) {
    var values: [String: NetworkAgentFieldValue] = [:]
    var statuses: [String: NetworkAgentFieldStatus] = [:]

    for field in fields {
      if let value = fieldValue(for: field, context: context) {
        values[field.rawValue] = value
        statuses[field.rawValue] = .available
      } else {
        statuses[field.rawValue] = .unavailable
      }
    }

    return (values, statuses)
  }

  /// Captures authorization, Wi-Fi, and network values exactly once per response.
  private func fieldResolutionContext() -> FieldResolutionContext {
    FieldResolutionContext(
      now: Date(),
      authorization: dependencies.authorizationSnapshot(),
      wifi: dependencies.currentWiFi(),
      network: dependencies.currentSystem()
    )
  }

  /// Resolves one requested field from the current context.
  private func fieldValue(
    for field: NetworkAgentField,
    context: FieldResolutionContext
  ) -> NetworkAgentFieldValue? {
    switch field {
    case .generatedAt:
      return .string(NetworkAgentSnapshot.dateString(from: context.now))
    case .ssid, .bssid, .interfaceName, .hardwareAddress, .power, .serviceActive, .rssi,
      .noise, .snr, .linkQuality, .txRate, .channel, .channelBand, .channelWidth, .security,
      .phyMode, .interfaceMode, .countryCode, .roaming, .ssidChangedAt, .interfaceChangedAt:
      return wifiFieldValue(for: field, wifi: context.wifi)
    case .primaryInterfaceIsTunnel, .primaryInterface, .activeTunnelInterface,
      .activeTunnelInterfaces, .ipv4Address, .ipv6Address, .defaultGateway, .dnsServers,
      .routeReachable, .routeUnavailableWithLocalAddress, .internetReachable, .captivePortal:
      return networkFieldValue(for: field, network: context.network)
    case .locationAuthorized, .locationPermissionState:
      return authorizationFieldValue(for: field, authorization: context.authorization)
    }
  }

  /// Resolves one Wi-Fi field value.
  private func wifiFieldValue(
    for field: NetworkAgentField,
    wifi: NetworkWiFiSnapshot
  ) -> NetworkAgentFieldValue? {
    switch field {
    case .ssid:
      return wifi.ssid.map(NetworkAgentFieldValue.string)
    case .bssid:
      return wifi.bssid.map(NetworkAgentFieldValue.string)
    case .interfaceName:
      return wifi.interfaceName.map(NetworkAgentFieldValue.string)
    case .hardwareAddress:
      return wifi.hardwareAddress.map(NetworkAgentFieldValue.string)
    case .power:
      return wifi.power.map(NetworkAgentFieldValue.bool)
    case .serviceActive:
      return wifi.serviceActive.map(NetworkAgentFieldValue.bool)
    case .rssi:
      return wifi.rssi.map(NetworkAgentFieldValue.int)
    case .noise:
      return wifi.noise.map(NetworkAgentFieldValue.int)
    case .snr:
      return wifi.snr.map(NetworkAgentFieldValue.int)
    case .linkQuality:
      return wifi.linkQuality.map(NetworkAgentFieldValue.int)
    case .txRate:
      return wifi.txRate.map(NetworkAgentFieldValue.int)
    case .channel:
      return wifi.channel.map(NetworkAgentFieldValue.int)
    case .channelBand:
      return wifi.channelBand.map(NetworkAgentFieldValue.string)
    case .channelWidth:
      return wifi.channelWidth.map(NetworkAgentFieldValue.string)
    case .security:
      return wifi.security.map(NetworkAgentFieldValue.string)
    case .phyMode:
      return wifi.phyMode.map(NetworkAgentFieldValue.string)
    case .interfaceMode:
      return wifi.interfaceMode.map(NetworkAgentFieldValue.string)
    case .countryCode:
      return wifi.countryCode.map(NetworkAgentFieldValue.string)
    case .roaming:
      return .bool(wifi.roaming)
    case .ssidChangedAt:
      return wifi.ssidChangedAt.map(NetworkAgentFieldValue.string)
    case .interfaceChangedAt:
      return wifi.interfaceChangedAt.map(NetworkAgentFieldValue.string)
    default:
      return nil
    }
  }

  /// Resolves one generic network field value.
  private func networkFieldValue(
    for field: NetworkAgentField,
    network: NetworkSystemSnapshot
  ) -> NetworkAgentFieldValue? {
    switch field {
    case .primaryInterfaceIsTunnel:
      return .bool(network.primaryInterfaceIsTunnel)
    case .primaryInterface:
      return network.primaryInterface.map(NetworkAgentFieldValue.string)
    case .activeTunnelInterface:
      return network.activeTunnelInterface.map(NetworkAgentFieldValue.string)
    case .activeTunnelInterfaces:
      return .stringList(network.activeTunnelInterfaces)
    case .ipv4Address:
      return network.ipv4Address.map(NetworkAgentFieldValue.string)
    case .ipv6Address:
      return network.ipv6Address.map(NetworkAgentFieldValue.string)
    case .defaultGateway:
      return network.defaultGateway.map(NetworkAgentFieldValue.string)
    case .dnsServers:
      return .stringList(network.dnsServers)
    case .routeReachable:
      return .bool(network.routeReachable)
    case .routeUnavailableWithLocalAddress:
      return .bool(network.routeUnavailableWithLocalAddress)
    case .internetReachable:
      return .bool(network.internetReachable)
    case .captivePortal:
      return network.captivePortal.map(NetworkAgentFieldValue.bool)
    default:
      return nil
    }
  }

  /// Resolves one authorization field value.
  private func authorizationFieldValue(
    for field: NetworkAgentField,
    authorization: NetworkAuthorizationSnapshot
  ) -> NetworkAgentFieldValue? {
    switch field {
    case .locationAuthorized:
      return .bool(authorization.isAuthorized)
    case .locationPermissionState:
      return .string(authorization.permissionState)
    default:
      return nil
    }
  }

  /// Returns the unauthorized response for one requested field list.
  private func unauthorizedFieldResponse(
    for fields: [NetworkAgentField],
    context: FieldResolutionContext,
    allowUnauthorizedFieldsWithoutLocation: Bool
  ) -> (
    values: [String: NetworkAgentFieldValue]?,
    statuses: [String: NetworkAgentFieldStatus]?,
    errorCode: NetworkAgentErrorCode?
  ) {
    let protectedFields = fields.filter(fieldRequiresLocationAuthorization)
    guard !protectedFields.isEmpty else {
      let response = resolvedFieldResponse(for: fields, context: context)
      return (response.values, response.statuses, nil)
    }

    guard allowUnauthorizedFieldsWithoutLocation else {
      let statuses = Dictionary(
        uniqueKeysWithValues: protectedFields.map {
          ($0.rawValue, NetworkAgentFieldStatus.permissionDenied)
        }
      )
      return (nil, statuses, .permissionDenied)
    }

    let allowedFields = fields.filter { !fieldRequiresLocationAuthorization($0) }
    var response = resolvedFieldResponse(for: allowedFields, context: context)
    for field in protectedFields {
      response.statuses[field.rawValue] = .permissionDenied
    }

    return (response.values, response.statuses, nil)
  }

  /// Returns whether the field should be hidden without location authorization.
  private func fieldRequiresLocationAuthorization(_ field: NetworkAgentField) -> Bool {
    networkAgentFieldRequiresLocationAuthorization(field)
  }
}
