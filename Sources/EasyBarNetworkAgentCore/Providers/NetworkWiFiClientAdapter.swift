@preconcurrency import CoreWLAN

/// Narrow CoreWLAN client surface used by the monitor and its lifecycle tests.
@MainActor
protocol NetworkWiFiClientAdapter: AnyObject {
  var delegate: CWEventDelegate? { get set }

  /// Starts monitoring event.
  func startMonitoringEvent(with eventType: CWEventType) throws
  /// Stops monitoring all events.
  func stopMonitoringAllEvents() throws
  /// Returns the interface.
  func interface() -> CWInterface?
}

/// Production adapter around the process-wide CoreWLAN client.
@MainActor
final class CoreWLANClientAdapter: NetworkWiFiClientAdapter {
  private let client: CWWiFiClient

  /// Creates a core wlan client adapter.
  init(client: CWWiFiClient = .shared()) {
    self.client = client
  }

  var delegate: CWEventDelegate? {
    get { client.delegate as? CWEventDelegate }
    set { client.delegate = newValue }
  }

  /// Starts monitoring event.
  func startMonitoringEvent(with eventType: CWEventType) throws {
    try client.startMonitoringEvent(with: eventType)
  }

  /// Stops monitoring all events.
  func stopMonitoringAllEvents() throws {
    try client.stopMonitoringAllEvents()
  }

  /// Returns the interface.
  func interface() -> CWInterface? {
    client.interface()
  }
}
