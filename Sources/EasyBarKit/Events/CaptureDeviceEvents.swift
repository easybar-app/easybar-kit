import EasyBarShared
import Foundation

/// Demand-driven camera and microphone event source for subscribed consumers.
@MainActor
final class CaptureDeviceEvents {
  static let orderedEvents: [AppEvent] = [
    .captureDevicesChanged,
    .cameraActivityChanged,
    .microphoneActivityChanged,
    .captureActivityChanged,
  ]

  static let eventNames = Set(orderedEvents.map(\.rawValue))

  private let logger: ProcessLogger
  private let eventHub: EventHub
  private let inventoryMonitor: CaptureDeviceInventoryMonitoring
  private var started = false
  private(set) var snapshot = CaptureDeviceSnapshot.empty

  /// Creates a capture device events.
  init(
    logger: ProcessLogger,
    eventHub: EventHub,
    inventoryMonitor: CaptureDeviceInventoryMonitoring? = nil
  ) {
    self.logger = logger
    self.eventHub = eventHub
    self.inventoryMonitor =
      inventoryMonitor ?? SystemCaptureDeviceInventoryMonitor(logger: logger)
  }

  /// Starts capture-device observation when at least one subscriber requires it.
  func start() {
    guard !started else { return }
    started = true

    inventoryMonitor.onChange = { [weak self] in
      self?.handleInventoryChange()
    }
    inventoryMonitor.start()
    snapshot = Self.makeSnapshot(from: inventoryMonitor.devices)

    logger.debug(
      "subscribed capture device events",
      .field("cameras", snapshot.cameras.count),
      .field("microphones", snapshot.microphones.count)
    )
  }

  /// Stops all device and activity observers.
  func stop() {
    guard started else { return }
    started = false
    inventoryMonitor.stop()
    inventoryMonitor.onChange = nil
    snapshot = .empty
    logger.debug("unsubscribed capture device events")
  }

  /// Publishes the current snapshot for newly added subscriptions.
  func publishCurrentSnapshot(for eventNames: Set<String>) {
    guard started else { return }

    let events = Self.orderedEvents.filter { eventNames.contains($0.rawValue) }
    emit(events, snapshot: snapshot)
  }

  /// Handles inventory change.
  private func handleInventoryChange() {
    guard started else { return }
    applySnapshot(Self.makeSnapshot(from: inventoryMonitor.devices))
  }

  /// Applies snapshot.
  private func applySnapshot(_ next: CaptureDeviceSnapshot) {
    let previous = snapshot
    snapshot = next

    let cameraActivityChanged =
      Self.activeDeviceIDs(in: previous.cameras) != Self.activeDeviceIDs(in: next.cameras)
    let microphoneActivityChanged =
      Self.activeDeviceIDs(in: previous.microphones) != Self.activeDeviceIDs(in: next.microphones)

    var events: [AppEvent] = []
    if Self.deviceIdentities(in: previous) != Self.deviceIdentities(in: next) {
      events.append(.captureDevicesChanged)
    }
    if cameraActivityChanged {
      events.append(.cameraActivityChanged)
    }
    if microphoneActivityChanged {
      events.append(.microphoneActivityChanged)
    }
    let captureActivityChanged = cameraActivityChanged || microphoneActivityChanged
    if captureActivityChanged {
      events.append(.captureActivityChanged)
    }

    guard !events.isEmpty else { return }

    logger.debug(
      "capture device state changed",
      .field("events", events.map(\.rawValue).joined(separator: ",")),
      .field("camera_active", next.cameraActive),
      .field("microphone_active", next.microphoneActive),
      .field("cameras", next.cameras.count),
      .field("microphones", next.microphones.count)
    )
    emit(events, snapshot: next)
  }

  /// Emits the prepared value.
  private func emit(_ events: [AppEvent], snapshot: CaptureDeviceSnapshot) {
    guard !events.isEmpty else { return }

    let eventHub = self.eventHub
    Task {
      for event in events {
        await eventHub.emit(
          .app(
            event,
            source: "capture_devices",
            capture: snapshot
          )
        )
      }
    }
  }

  /// Creates snapshot.
  private static func makeSnapshot(
    from devices: [CaptureDeviceState]
  ) -> CaptureDeviceSnapshot {
    let cameras =
      devices
      .filter { $0.kind == .camera }
      .sorted(by: deviceSort)
    let microphones =
      devices
      .filter { $0.kind == .microphone }
      .sorted(by: deviceSort)

    return CaptureDeviceSnapshot(cameras: cameras, microphones: microphones)
  }

  /// Returns the device sort.
  private static func deviceSort(_ lhs: CaptureDeviceState, _ rhs: CaptureDeviceState) -> Bool {
    if lhs.name != rhs.name {
      return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
    return lhs.id < rhs.id
  }

  /// Returns the device identities.
  private static func deviceIdentities(
    in snapshot: CaptureDeviceSnapshot
  ) -> [CaptureDeviceIdentity] {
    (snapshot.cameras + snapshot.microphones).map {
      CaptureDeviceIdentity(
        id: $0.id,
        name: $0.name,
        kind: $0.kind,
        connected: $0.connected
      )
    }
  }

  /// Returns the active device IDs.
  private static func activeDeviceIDs(
    in devices: [CaptureDeviceState]
  ) -> [String] {
    devices.filter(\.active).map(\.id)
  }
}

/// Stores capture device identity data.
private struct CaptureDeviceIdentity: Equatable {
  /// The stable identifier for this capture device identity.
  let id: String
  /// The name for this capture device identity.
  let name: String
  /// The kind for this capture device identity.
  let kind: CaptureDeviceKind
  /// Whether this capture device identity is connected.
  let connected: Bool
}

/// Injectable inventory boundary used by the event source and unit tests.
@MainActor
protocol CaptureDeviceInventoryMonitoring: AnyObject {
  var onChange: (() -> Void)? { get set }
  var devices: [CaptureDeviceState] { get }

  /// Starts the associated service.
  func start()
  /// Stops the associated service.
  func stop()
}
