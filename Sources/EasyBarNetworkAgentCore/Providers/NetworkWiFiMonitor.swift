@preconcurrency import CoreWLAN
import EasyBarShared
import Foundation

/// Watches CoreWLAN Wi-Fi state.
@MainActor
final class NetworkWiFiMonitor: NSObject, CWEventDelegate {
  private let smoothingFactor = 0.35

  /// Stores tracking state data.
  private struct TrackingState {
    /// The smoothed RSSI for this tracking state.
    var smoothedRSSI: Double?
    /// The stable identifier for this tracking state.
    var lastSSID: String?
    /// The stable identifier for this tracking state.
    var lastBSSID: String?
    /// The last interface for this tracking state.
    var lastInterface: String?
    /// The SSID changed at for this tracking state.
    var ssidChangedAt: Date?
    /// The interface changed at for this tracking state.
    var interfaceChangedAt: Date?
    /// Whether the roaming option is enabled for this tracking state.
    var roaming = false
  }

  private let componentName: String
  private let logger: ProcessLogger
  private let makeClient: @MainActor () -> NetworkWiFiClientAdapter
  private var trackingState = TrackingState()
  private var cachedSnapshot = NetworkWiFiSnapshot.empty
  private var onChange: (() -> Void)?
  private var wifiClient: NetworkWiFiClientAdapter?

  /// Creates one Wi-Fi monitor that logs through the provided logger.
  init(
    componentName: String,
    logger: ProcessLogger,
    makeClient: @escaping @MainActor () -> NetworkWiFiClientAdapter = {
      CoreWLANClientAdapter()
    }
  ) {
    self.componentName = componentName
    self.logger = logger
    self.makeClient = makeClient
    super.init()
  }

  /// Starts listening for Wi-Fi changes.
  func start(onChange: @escaping () -> Void) {
    self.onChange = onChange

    guard wifiClient == nil else {
      return
    }

    let client = makeClient()
    client.delegate = self
    wifiClient = client

    do {
      try client.startMonitoringEvent(with: .ssidDidChange)
      try client.startMonitoringEvent(with: .bssidDidChange)
      try client.startMonitoringEvent(with: .countryCodeDidChange)
      try client.startMonitoringEvent(with: .linkDidChange)
      try client.startMonitoringEvent(with: .linkQualityDidChange)
      try client.startMonitoringEvent(with: .modeDidChange)
      try client.startMonitoringEvent(with: .powerDidChange)
      try client.startMonitoringEvent(with: .scanCacheUpdated)
      refreshState(now: Date())
      logger.info(
        "\(componentName) subscribed",
        .field("event", "wifi_change"),
      )
    } catch {
      let registrationError = error

      do {
        try client.stopMonitoringAllEvents()
        client.delegate = nil
        if wifiClient === client {
          wifiClient = nil
        }
      } catch {
        // Keep the client retained so a later stop can retry cleanup instead
        // of registering over a partially active callback set.
        logger.error(
          "failed to roll back partial \(componentName) Wi-Fi monitoring",
          .field("error", error),
        )
      }

      logger.warn(
        "failed to subscribe \(componentName) Wi-Fi events",
        .field("error", registrationError),
      )
    }
  }

  /// Stops Wi-Fi monitoring.
  func stop() {
    onChange = nil

    if let wifiClient {
      do {
        try wifiClient.stopMonitoringAllEvents()
        wifiClient.delegate = nil
        if self.wifiClient === wifiClient {
          self.wifiClient = nil
        }
      } catch {
        // Retain the client after a failed stop so a later stop or restart can
        // retry cleanup without creating duplicate event registrations.
        logger.warn(
          "failed to stop Wi-Fi monitoring",
          .field("error", error),
        )
      }
    }

    trackingState = TrackingState()
    cachedSnapshot = .empty
  }

  /// Refreshes cached Wi-Fi state in response to one event or polling tick.
  func refreshState(now: Date) {
    guard let interface = wifiClient?.interface() else {
      cachedSnapshot = .empty
      trackingState.smoothedRSSI = nil
      return
    }

    let ssid = normalized(interface.ssid())
    let bssid = normalized(interface.bssid())
    let interfaceName = normalized(interface.interfaceName)
    let hardwareAddress = normalized(interface.hardwareAddress())
    let power = interface.powerOn()
    let serviceActive = interface.serviceActive()
    let rssi = smoothedRSSIValue(from: validMeasurement(interface.rssiValue()))
    let noise = validMeasurement(interface.noiseMeasurement())
    let snr = makeSNR(rssi: rssi, noise: noise)
    let linkQuality = makeLinkQuality(snr: snr)
    let channelInfo = interface.wlanChannel()
    let changeTracking = updateChangeTracking(
      ssid: ssid,
      bssid: bssid,
      interface: interfaceName,
      now: now
    )

    cachedSnapshot = NetworkWiFiSnapshot(
      ssid: ssid,
      bssid: bssid,
      interfaceName: interfaceName,
      hardwareAddress: hardwareAddress,
      power: power,
      serviceActive: serviceActive,
      rssi: rssi,
      noise: noise,
      snr: snr,
      linkQuality: linkQuality,
      txRate: NetworkWiFiNormalization.transmitRate(interface.transmitRate()),
      channel: channelInfo.flatMap { Int(exactly: $0.channelNumber) },
      channelBand: channelInfo.map {
        NetworkWiFiNormalization.channelBand(rawValue: $0.channelBand.rawValue)
      },
      channelWidth: channelInfo.map {
        NetworkWiFiNormalization.channelWidth(rawValue: $0.channelWidth.rawValue)
      },
      security: NetworkWiFiNormalization.security(rawValue: interface.security().rawValue),
      phyMode: NetworkWiFiNormalization.phyMode(rawValue: interface.activePHYMode().rawValue),
      interfaceMode: NetworkWiFiNormalization.interfaceMode(
        rawValue: interface.interfaceMode().rawValue
      ),
      countryCode: normalized(interface.countryCode()),
      roaming: changeTracking.roaming,
      ssidChangedAt: changeTracking.ssidChangedAt,
      interfaceChangedAt: changeTracking.interfaceChangedAt
    )
  }

  /// Returns the last monitor-produced state without changing smoothing or timestamps.
  func currentState() -> NetworkWiFiSnapshot {
    cachedSnapshot
  }

  /// Handles the SSID did change for Wi-Fi interface callback.
  nonisolated func ssidDidChangeForWiFiInterface(withName interfaceName: String) {
    enqueueChange(label: "SSID", interfaceName: interfaceName)
  }

  /// Handles the BSSID did change for Wi-Fi interface callback.
  nonisolated func bssidDidChangeForWiFiInterface(withName interfaceName: String) {
    enqueueChange(label: "BSSID", interfaceName: interfaceName)
  }

  /// Handles the country code did change for Wi-Fi interface callback.
  nonisolated func countryCodeDidChangeForWiFiInterface(withName interfaceName: String) {
    enqueueChange(label: "country code", interfaceName: interfaceName)
  }

  /// Handles the link did change for Wi-Fi interface callback.
  nonisolated func linkDidChangeForWiFiInterface(withName interfaceName: String) {
    enqueueChange(label: "link", interfaceName: interfaceName)
  }

  /// Handles the link quality did change for Wi-Fi interface callback.
  nonisolated func linkQualityDidChangeForWiFiInterface(
    withName interfaceName: String,
    rssi: Int,
    transmitRate: Double
  ) {
    Task { @MainActor [weak self] in
      guard let self else { return }
      self.logger.info(
        "\(self.componentName) Wi-Fi link quality changed",
        .field("interface", interfaceName),
        .field("rssi", rssi),
        .field("tx_rate", transmitRate),
      )
      self.refreshAndNotify()
    }
  }

  /// Handles the mode did change for Wi-Fi interface callback.
  nonisolated func modeDidChangeForWiFiInterface(withName interfaceName: String) {
    enqueueChange(label: "mode", interfaceName: interfaceName)
  }

  /// Handles the power state did change for Wi-Fi interface callback.
  nonisolated func powerStateDidChangeForWiFiInterface(withName interfaceName: String) {
    enqueueChange(label: "power", interfaceName: interfaceName)
  }

  /// Returns the scan cache updated for Wi-Fi interface.
  nonisolated func scanCacheUpdatedForWiFiInterface(withName interfaceName: String) {
    Task { @MainActor [weak self] in
      guard let self else { return }
      self.logger.debug(
        "\(self.componentName) Wi-Fi scan cache updated",
        .field("interface", interfaceName),
      )
      self.refreshAndNotify()
    }
  }

  /// Hops one CoreWLAN callback onto the monitor's lifecycle actor.
  private nonisolated func enqueueChange(label: String, interfaceName: String) {
    Task { @MainActor [weak self] in
      guard let self else { return }
      self.logger.info(
        "\(self.componentName) Wi-Fi \(label) changed",
        .field("interface", interfaceName),
      )
      self.refreshAndNotify()
    }
  }

  /// Refreshes the cached sample and notifies the current lifecycle callback.
  private func refreshAndNotify() {
    guard wifiClient != nil else { return }
    refreshState(now: Date())
    onChange?()
  }

  /// Smooths RSSI so the UI does not jump on every monitor sample.
  private func smoothedRSSIValue(from rssi: Int?) -> Int? {
    guard let rssi else {
      trackingState.smoothedRSSI = nil
      logger.debug(
        "\(componentName) RSSI unavailable",
        .field("rssi", "<none>"),
      )
      return nil
    }

    guard let smoothedRSSI = trackingState.smoothedRSSI else {
      trackingState.smoothedRSSI = Double(rssi)
      return rssi
    }

    trackingState.smoothedRSSI =
      (smoothedRSSI * (1 - smoothingFactor)) + (Double(rssi) * smoothingFactor)
    return Int((trackingState.smoothedRSSI ?? Double(rssi)).rounded())
  }

  /// Updates cached SSID and interface change tracking for a new sample.
  private func updateChangeTracking(
    ssid: String?,
    bssid: String?,
    interface: String?,
    now: Date
  ) -> (roaming: Bool, ssidChangedAt: String?, interfaceChangedAt: String?) {
    if trackingState.lastSSID != ssid {
      trackingState.ssidChangedAt = now
    }

    if trackingState.lastInterface != interface {
      trackingState.interfaceChangedAt = now
    }

    trackingState.roaming =
      trackingState.lastSSID == ssid
      && ssid != nil
      && trackingState.lastBSSID != nil
      && bssid != nil
      && trackingState.lastBSSID != bssid

    trackingState.lastSSID = ssid
    trackingState.lastBSSID = bssid
    trackingState.lastInterface = interface

    return (
      roaming: trackingState.roaming,
      ssidChangedAt: trackingState.ssidChangedAt.map(NetworkAgentSnapshot.dateString(from:)),
      interfaceChangedAt: trackingState.interfaceChangedAt.map(
        NetworkAgentSnapshot.dateString(from:))
    )
  }

  /// Filters out unusable measurements from system APIs.
  private func validMeasurement(_ value: Int) -> Int? {
    value == 0 ? nil : value
  }

  /// Returns signal-to-noise ratio.
  private func makeSNR(rssi: Int?, noise: Int?) -> Int? {
    guard let rssi, let noise else { return nil }
    return rssi - noise
  }

  /// Returns a rough 0...100 link quality score.
  private func makeLinkQuality(snr: Int?) -> Int? {
    guard let snr else { return nil }
    return min(max((snr - 10) * 4, 0), 100)
  }

  /// Trims one optional string and drops empty values.
  private func normalized(_ value: String?) -> String? {
    guard let value else { return nil }

    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
