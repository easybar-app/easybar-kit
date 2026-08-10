import EasyBarShared
import Foundation

/// Publishes network-agent snapshots into app state and emits matching runtime events.
final class NetworkAgentSnapshotPublisher: @unchecked Sendable {
  /// Returns whether asynchronous publish work still belongs to the latest publication.
  private let isCurrent: (UInt64) -> Bool
  private let store: NativeWiFiStore
  private let eventHub: EventHub

  /// Creates one network-agent snapshot publisher.
  init(
    store: NativeWiFiStore,
    eventHub: EventHub,
    isCurrent: @escaping (UInt64) -> Bool = { _ in true }
  ) {
    self.store = store
    self.eventHub = eventHub
    self.isCurrent = isCurrent
  }

  /// Clears the shared Wi-Fi state and optionally emits the corresponding app events.
  func clear(notify: Bool, publicationID: UInt64) {
    Task { @MainActor in
      guard self.isCurrent(publicationID) else { return }
      let previous = self.store.snapshot
      let changed = self.store.clear()

      guard changed else { return }
      guard notify else { return }

      Task {
        await self.eventHub.emit(
          .app(
            .networkChange,
            primaryInterfaceIsTunnel: false
          ))

        if self.shouldEmitWiFiChangeAfterReset(previous: previous) {
          await self.eventHub.emit(.wifiChange)
        }
      }
    }
  }

  /// Publishes one snapshot to the shared store on the main queue and emits app events.
  func publish(snapshot: NetworkAgentSnapshot, publicationID: UInt64) {
    Task { @MainActor in
      guard self.isCurrent(publicationID) else { return }

      let previous = self.store.snapshot
      let changed = self.store.apply(snapshot: snapshot)

      guard changed else { return }

      Task {
        await self.eventHub.emit(
          .app(
            .networkChange,
            primaryInterfaceIsTunnel: snapshot.primaryInterfaceIsTunnel
          ))

        let ssidChanged = previous?.ssid != snapshot.ssid
        let interfaceChanged = previous?.interfaceName != snapshot.interfaceName

        guard ssidChanged || interfaceChanged else { return }

        if let interfaceName = snapshot.interfaceName, !interfaceName.isEmpty {
          await self.eventHub.emit(.app(.wifiChange, interfaceName: interfaceName))
        } else {
          await self.eventHub.emit(.wifiChange)
        }
      }
    }
  }

  /// Returns whether clearing the published state should also emit a Wi-Fi change event.
  private func shouldEmitWiFiChangeAfterReset(previous: NetworkAgentSnapshot?) -> Bool {
    return previous?.ssid != nil || previous?.interfaceName != nil
  }
}
