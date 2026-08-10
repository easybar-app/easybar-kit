import Foundation
import XCTest

@testable import EasyBarKit
@testable import EasyBarShared

@MainActor
final class NetworkAgentClientTests: XCTestCase {
  func testTransientDisconnectClearsPublishedSnapshot() async throws {
    let logger = ProcessLogger(
      label: "network.client.tests",
      minimumLevel: .error,
      outputStream: nil,
      errorStream: nil
    )
    let temporaryDirectory = URL(fileURLWithPath: "/tmp", isDirectory: true)
      .appendingPathComponent("eb-network-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: temporaryDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let socketPath = temporaryDirectory.appendingPathComponent("agent.sock").path
    let server = LineSocketServerTransport<Void, NetworkAgentRequest, NetworkAgentMessage>(
      socketPath: socketPath,
      serverLabel: "network client tests",
      logger: logger
    )
    XCTAssertTrue(
      server.start { fd, _ in
        server.addSubscriber((), for: fd)
        _ = server.send(NetworkAgentMessage(kind: .subscribed), to: fd)
        _ = server.send(
          NetworkAgentMessage(kind: .fields, fields: Self.snapshotFields(ssid: "Office")),
          to: fd
        )
        return .keepOpen
      }
    )
    defer { server.stop() }

    let store = NativeWiFiStore(logger: logger)
    let eventHub = EventHub(logger: logger, enqueueLuaEvent: { _ in })
    let client = NetworkAgentClient(
      logger: logger,
      config: ConfigSnapshot.NetworkAgent(
        enabled: true,
        socketPath: socketPath,
        refreshIntervalSeconds: 60,
        allowUnauthorizedNonSensitiveFields: false
      ),
      nativeWiFiStore: store,
      eventHub: eventHub
    )
    client.start()
    defer { client.stop() }

    try await waitUntil("network snapshot") {
      store.snapshot?.ssid == "Office"
    }

    server.stop()

    try await waitUntil("network snapshot clear after disconnect") {
      store.snapshot == nil
    }
  }

  private nonisolated static func snapshotFields(ssid: String) -> [String: NetworkAgentFieldValue] {
    let generatedAt = NetworkAgentSnapshot.dateString(
      from: Date(timeIntervalSince1970: 1_700_000_000)
    )
    return [
      NetworkAgentField.locationAuthorized.rawValue: .bool(true),
      NetworkAgentField.locationPermissionState.rawValue: .string("authorized"),
      NetworkAgentField.generatedAt.rawValue: .string(generatedAt),
      NetworkAgentField.primaryInterfaceIsTunnel.rawValue: .bool(false),
      NetworkAgentField.ssid.rawValue: .string(ssid),
      NetworkAgentField.interfaceName.rawValue: .string("en0"),
    ]
  }

  private func waitUntil(
    _ description: String,
    timeoutNanoseconds: UInt64 = 1_000_000_000,
    condition: @escaping @MainActor () -> Bool
  ) async throws {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
    while DispatchTime.now().uptimeNanoseconds < deadline {
      if condition() { return }
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTFail("Timed out waiting for \(description)")
  }
}
