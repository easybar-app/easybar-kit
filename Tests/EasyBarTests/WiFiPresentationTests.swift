import EasyBarShared
import Foundation
import XCTest

@testable import EasyBarKit

final class WiFiPresentationTests: ConfigLoaderTestCase {
  /// Verifies that parsed Wi-Fi field toggles render through the shared field catalog.
  func testParsedWiFiFieldsRenderInCatalogOrderWithLabels() throws {
    let config = Config.makeUnloadedConfig()
    let configFileURL = tempDirectoryURL.appendingPathComponent("wifi-fields.toml")

    try writeConfig(
      """
      [builtins.wifi.content]
      mode = "details"

      [builtins.wifi.fields]
      tx_rate = true
      ssid = true
      rssi = true
      ipv4_address = true
      """,
      to: configFileURL
    )

    setEnvironmentValue(configFileURL.path, for: SharedEnvironmentKeys.configPath)

    let error = config.reload()

    XCTAssertNil(error)
    XCTAssertTrue(config.builtinWiFi.fields.ssid)
    XCTAssertTrue(config.builtinWiFi.fields.ipv4Address)
    XCTAssertTrue(config.builtinWiFi.fields.rssi)
    XCTAssertTrue(config.builtinWiFi.fields.txRate)

    let presentation = WiFiPresentation(
      snapshot: networkSnapshot(),
      config: config.builtinWiFi
    )

    guard case .details(let rows) = presentation.content else {
      return XCTFail("Expected Wi-Fi details content")
    }

    XCTAssertEqual(rows.map(\.labelText), ["SSID", "IPv4 Address", "Signal", "Rate"])
    XCTAssertEqual(
      rows.map(\.valueText),
      ["Office Wi-Fi", "192.0.2.10", "-60 dBm", "780 Mbps"]
    )
  }

  @MainActor
  func testWiFiDetailsSurfaceAlwaysPresentsPopupWhileIdle() throws {
    let root = try renderedWiFiRootNode(surface: .always)

    XCTAssertEqual(root.popupPresented, true)
  }

  @MainActor
  func testWiFiDetailsSurfaceHoverDoesNotPresentPopupWhileIdle() throws {
    let root = try renderedWiFiRootNode(surface: .hover)

    XCTAssertEqual(root.popupPresented, false)
  }

  /// Returns one rendered Wi-Fi root node for a details-mode surface behavior test.
  @MainActor
  private func renderedWiFiRootNode(
    surface: Config.BuiltinWiFiContentSurface
  ) throws -> WidgetNodeState {
    let config = Config.makeUnloadedConfig()
    let configFileURL = tempDirectoryURL.appendingPathComponent("wifi-details-surface.toml")

    try writeConfig(
      """
      [builtins.wifi.content]
      mode = "details"
      surface = "\(surface.rawValue)"

      [builtins.wifi.fields]
      ssid = true
      """,
      to: configFileURL
    )

    setEnvironmentValue(configFileURL.path, for: SharedEnvironmentKeys.configPath)

    let error = config.reload()
    XCTAssertNil(error)

    let network = networkSnapshot()
    let presentation = WiFiPresentation(snapshot: network, config: config.builtinWiFi)
    let detailsContentVisible = config.builtinWiFi.surface == .always
    let snapshot = WiFiNativeWidget.Snapshot(
      config: config.builtinWiFi,
      network: network,
      content: presentation.content,
      signalLevel: presentation.signalLevel,
      visualState: presentation.visualState,
      activeColorHex: presentation.activeColorHex,
      inactiveColorHex: presentation.inactiveColorHex,
      inlineContentVisible: false,
      detailsContentVisible: detailsContentVisible
    )
    let nodes = WiFiRenderer(rootID: "builtin_wifi").makeNodes(snapshot: snapshot)

    guard let root = nodes.first(where: { $0.id == "builtin_wifi" }) else {
      throw NSError(domain: "WiFiPresentationTests", code: 1)
    }

    return root
  }

  /// Returns one populated network snapshot for Wi-Fi presentation tests.
  private func networkSnapshot() -> NetworkAgentSnapshot {
    NetworkAgentSnapshot(
      accessGranted: true,
      permissionState: "authorized",
      generatedAt: Date(timeIntervalSince1970: 0),
      ssid: "Office Wi-Fi",
      ipv4Address: "192.0.2.10",
      ipv6Address: nil,
      bssid: nil,
      interfaceName: nil,
      hardwareAddress: nil,
      power: nil,
      serviceActive: nil,
      primaryInterfaceIsTunnel: false,
      rssi: -60,
      noise: nil,
      snr: nil,
      linkQuality: nil,
      txRate: 780,
      channel: nil,
      channelBand: nil,
      channelWidth: nil,
      security: nil,
      phyMode: nil,
      interfaceMode: nil,
      countryCode: nil,
      roaming: nil,
      ssidChangedAt: nil,
      interfaceChangedAt: nil
    )
  }
}
