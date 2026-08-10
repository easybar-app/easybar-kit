import EasyBarShared
import Foundation

/// Replayable event definitions in stable invalidation order.
enum EventReplayCatalog {
  static let orderedEvents: [AppEvent] = [
    .systemWoke,
    .powerSourceChange,
    .chargingStateChange,
    .wifiChange,
    .networkChange,
    .volumeChange,
    .muteChange,
    .calendarChange,
    .minuteTick,
    .secondTick,
    .focusChange,
    .workspaceChange,
    .spaceModeChange,
  ]
  static func isReplayable(_ eventName: String) -> Bool {
    orderedEvents.contains { $0.rawValue == eventName }
  }

  static func payloads(
    for eventNames: Set<String>,
    wifiSnapshotProvider: @MainActor @Sendable () -> NetworkAgentSnapshot? = { nil }
  ) async -> [EasyBarEventPayload] {
    var payloads: [EasyBarEventPayload] = []
    for event in orderedEvents where eventNames.contains(event.rawValue) {
      payloads.append(
        await currentPayload(for: event, wifiSnapshotProvider: wifiSnapshotProvider)
      )
    }
    return payloads
  }

  private static func currentPayload(
    for event: AppEvent,
    wifiSnapshotProvider: @MainActor @Sendable () -> NetworkAgentSnapshot?
  ) async -> EasyBarEventPayload {
    switch event {
    case .wifiChange:
      let interfaceName = await MainActor.run {
        wifiSnapshotProvider()?.interfaceName
      }

      if let interfaceName, !interfaceName.isEmpty {
        return .app(.wifiChange, interfaceName: interfaceName)
      }

      return .app(.wifiChange)

    case .networkChange:
      let isTunnel = await MainActor.run {
        wifiSnapshotProvider()?.primaryInterfaceIsTunnel ?? false
      }

      return .app(.networkChange, primaryInterfaceIsTunnel: isTunnel)

    default:
      return .app(event)
    }
  }
}
