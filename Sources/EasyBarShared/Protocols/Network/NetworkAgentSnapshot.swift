import Foundation

/// Version information returned by the network agent.
public struct NetworkAgentVersion: Codable, Equatable, Sendable {
  /// The application version embedded in the network-agent build.
  public var appVersion: String
  /// Shared EasyBar IPC protocol version.
  public var protocolVersion: String

  /// Creates one network-agent version payload.
  public init(appVersion: String, protocolVersion: String) {
    self.appVersion = appVersion
    self.protocolVersion = protocolVersion
  }
}

/// Full network snapshot returned by the agent.
public struct NetworkAgentSnapshot: Codable, Equatable, Sendable {
  /// Formats one network-agent timestamp for wire or display use.
  public static func dateString(from date: Date) -> String {
    makeDateFormatter().string(from: date)
  }

  /// Parses one network-agent timestamp from the wire format.
  public static func date(from string: String) -> Date? {
    makeDateFormatter().date(from: string)
  }

  private static func makeDateFormatter() -> ISO8601DateFormatter {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }

  /// Standard field set required to build a snapshot from field values.
  public static let snapshotFieldSet: [NetworkAgentField] = [
    .locationAuthorized,
    .locationPermissionState,
    .generatedAt,
    .ssid,
    .ipv4Address,
    .ipv6Address,
    .bssid,
    .interfaceName,
    .hardwareAddress,
    .power,
    .serviceActive,
    .primaryInterfaceIsTunnel,
    .rssi,
    .noise,
    .snr,
    .linkQuality,
    .txRate,
    .channel,
    .channelBand,
    .channelWidth,
    .security,
    .phyMode,
    .interfaceMode,
    .countryCode,
    .roaming,
    .ssidChangedAt,
    .interfaceChangedAt,
  ]

  /// Whether location/Wi-Fi access is currently granted.
  public var accessGranted: Bool
  /// Current permission state string.
  public var permissionState: String
  /// Snapshot generation time.
  public var generatedAt: Date
  /// Active Wi-Fi SSID when available.
  public var ssid: String?
  /// Primary network IPv4 address when available.
  public var ipv4Address: String?
  /// Primary network IPv6 address when available.
  public var ipv6Address: String?
  /// Active Wi-Fi BSSID when available.
  public var bssid: String?
  /// Active Wi-Fi interface name when available.
  public var interfaceName: String?
  /// Active Wi-Fi hardware address when available.
  public var hardwareAddress: String?
  /// Wi-Fi power state when available.
  public var power: Bool?
  /// Wi-Fi service availability when available.
  public var serviceActive: Bool?
  /// Whether the current primary interface is a tunnel.
  public var primaryInterfaceIsTunnel: Bool
  /// Raw or smoothed RSSI value when available.
  public var rssi: Int?
  /// Noise floor when available.
  public var noise: Int?
  /// Signal-to-noise ratio when available.
  public var snr: Int?
  /// Link quality percentage when available.
  public var linkQuality: Int?
  /// Current transmit rate when available.
  public var txRate: Int?
  /// Current Wi-Fi channel when available.
  public var channel: Int?
  /// Current Wi-Fi band when available.
  public var channelBand: String?
  /// Current Wi-Fi channel width when available.
  public var channelWidth: String?
  /// Current Wi-Fi security mode when available.
  public var security: String?
  /// Current Wi-Fi PHY mode when available.
  public var phyMode: String?
  /// Current Wi-Fi interface mode when available.
  public var interfaceMode: String?
  /// Current Wi-Fi country code when available.
  public var countryCode: String?
  /// Whether roaming was detected when available.
  public var roaming: Bool?
  /// Last SSID change timestamp when available.
  public var ssidChangedAt: String?
  /// Last interface change timestamp when available.
  public var interfaceChangedAt: String?

  /// Creates one network snapshot payload.
  public init(
    accessGranted: Bool,
    permissionState: String,
    generatedAt: Date,
    ssid: String?,
    ipv4Address: String?,
    ipv6Address: String?,
    bssid: String?,
    interfaceName: String?,
    hardwareAddress: String?,
    power: Bool?,
    serviceActive: Bool?,
    primaryInterfaceIsTunnel: Bool,
    rssi: Int?,
    noise: Int?,
    snr: Int?,
    linkQuality: Int?,
    txRate: Int?,
    channel: Int?,
    channelBand: String?,
    channelWidth: String?,
    security: String?,
    phyMode: String?,
    interfaceMode: String?,
    countryCode: String?,
    roaming: Bool?,
    ssidChangedAt: String?,
    interfaceChangedAt: String?
  ) {
    self.accessGranted = accessGranted
    self.permissionState = permissionState
    self.generatedAt = generatedAt
    self.ssid = ssid
    self.ipv4Address = ipv4Address
    self.ipv6Address = ipv6Address
    self.bssid = bssid
    self.interfaceName = interfaceName
    self.hardwareAddress = hardwareAddress
    self.power = power
    self.serviceActive = serviceActive
    self.primaryInterfaceIsTunnel = primaryInterfaceIsTunnel
    self.rssi = rssi
    self.noise = noise
    self.snr = snr
    self.linkQuality = linkQuality
    self.txRate = txRate
    self.channel = channel
    self.channelBand = channelBand
    self.channelWidth = channelWidth
    self.security = security
    self.phyMode = phyMode
    self.interfaceMode = interfaceMode
    self.countryCode = countryCode
    self.roaming = roaming
    self.ssidChangedAt = ssidChangedAt
    self.interfaceChangedAt = interfaceChangedAt
  }

  /// Builds one typed snapshot from field-query values.
  public init?(fields: [String: NetworkAgentFieldValue]) {
    guard
      let accessGranted = fields[NetworkAgentField.locationAuthorized.rawValue]?.boolValue,
      let permissionState = fields[NetworkAgentField.locationPermissionState.rawValue]?.stringValue,
      let generatedAtRaw = fields[NetworkAgentField.generatedAt.rawValue]?.stringValue,
      let generatedAt = Self.date(from: generatedAtRaw),
      let primaryInterfaceIsTunnel = fields[NetworkAgentField.primaryInterfaceIsTunnel.rawValue]?
        .boolValue
    else {
      return nil
    }

    self.init(
      accessGranted: accessGranted,
      permissionState: permissionState,
      generatedAt: generatedAt,
      ssid: fields[NetworkAgentField.ssid.rawValue]?.stringValue,
      ipv4Address: fields[NetworkAgentField.ipv4Address.rawValue]?.stringValue,
      ipv6Address: fields[NetworkAgentField.ipv6Address.rawValue]?.stringValue,
      bssid: fields[NetworkAgentField.bssid.rawValue]?.stringValue,
      interfaceName: fields[NetworkAgentField.interfaceName.rawValue]?.stringValue,
      hardwareAddress: fields[NetworkAgentField.hardwareAddress.rawValue]?.stringValue,
      power: fields[NetworkAgentField.power.rawValue]?.boolValue,
      serviceActive: fields[NetworkAgentField.serviceActive.rawValue]?.boolValue,
      primaryInterfaceIsTunnel: primaryInterfaceIsTunnel,
      rssi: fields[NetworkAgentField.rssi.rawValue]?.intValue,
      noise: fields[NetworkAgentField.noise.rawValue]?.intValue,
      snr: fields[NetworkAgentField.snr.rawValue]?.intValue,
      linkQuality: fields[NetworkAgentField.linkQuality.rawValue]?.intValue,
      txRate: fields[NetworkAgentField.txRate.rawValue]?.intValue,
      channel: fields[NetworkAgentField.channel.rawValue]?.intValue,
      channelBand: fields[NetworkAgentField.channelBand.rawValue]?.stringValue,
      channelWidth: fields[NetworkAgentField.channelWidth.rawValue]?.stringValue,
      security: fields[NetworkAgentField.security.rawValue]?.stringValue,
      phyMode: fields[NetworkAgentField.phyMode.rawValue]?.stringValue,
      interfaceMode: fields[NetworkAgentField.interfaceMode.rawValue]?.stringValue,
      countryCode: fields[NetworkAgentField.countryCode.rawValue]?.stringValue,
      roaming: fields[NetworkAgentField.roaming.rawValue]?.boolValue,
      ssidChangedAt: fields[NetworkAgentField.ssidChangedAt.rawValue]?.stringValue,
      interfaceChangedAt: fields[NetworkAgentField.interfaceChangedAt.rawValue]?.stringValue
    )
  }
}

/// Render-relevant signature used to suppress duplicate Wi-Fi UI updates.
public struct NetworkAgentSnapshotRenderSignature: Equatable, Sendable {
  public let accessGranted: Bool
  public let permissionState: String
  public let ssid: String?
  public let ipv4Address: String?
  public let ipv6Address: String?
  public let bssid: String?
  public let interfaceName: String?
  public let hardwareAddress: String?
  public let power: Bool?
  public let serviceActive: Bool?
  public let primaryInterfaceIsTunnel: Bool
  public let rssi: Int?
  public let noise: Int?
  public let snr: Int?
  public let linkQuality: Int?
  public let txRate: Int?
  public let channel: Int?
  public let channelBand: String?
  public let channelWidth: String?
  public let security: String?
  public let phyMode: String?
  public let interfaceMode: String?
  public let countryCode: String?
  public let roaming: Bool?
  public let ssidChangedAt: String?
  public let interfaceChangedAt: String?

  public init(snapshot: NetworkAgentSnapshot) {
    self.accessGranted = snapshot.accessGranted
    self.permissionState = snapshot.permissionState
    self.ssid = snapshot.ssid
    self.ipv4Address = snapshot.ipv4Address
    self.ipv6Address = snapshot.ipv6Address
    self.bssid = snapshot.bssid
    self.interfaceName = snapshot.interfaceName
    self.hardwareAddress = snapshot.hardwareAddress
    self.power = snapshot.power
    self.serviceActive = snapshot.serviceActive
    self.primaryInterfaceIsTunnel = snapshot.primaryInterfaceIsTunnel
    self.rssi = snapshot.rssi
    self.noise = snapshot.noise
    self.snr = snapshot.snr
    self.linkQuality = snapshot.linkQuality
    self.txRate = snapshot.txRate
    self.channel = snapshot.channel
    self.channelBand = snapshot.channelBand
    self.channelWidth = snapshot.channelWidth
    self.security = snapshot.security
    self.phyMode = snapshot.phyMode
    self.interfaceMode = snapshot.interfaceMode
    self.countryCode = snapshot.countryCode
    self.roaming = snapshot.roaming
    self.ssidChangedAt = snapshot.ssidChangedAt
    self.interfaceChangedAt = snapshot.interfaceChangedAt
  }
}

extension NetworkAgentSnapshot {
  /// Render-relevant identity used by native Wi-Fi consumers.
  public var renderSignature: NetworkAgentSnapshotRenderSignature {
    NetworkAgentSnapshotRenderSignature(snapshot: self)
  }
}

/// Message kinds sent by the network agent.
