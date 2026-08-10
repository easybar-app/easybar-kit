import Foundation

/// Default context-menu state provider backed by app-owned runtime services.
@MainActor
final class BarContextMenuStateProvider {
  /// Wi-Fi state store owned by the app service graph.
  private let nativeWiFiStore: NativeWiFiStore
  /// Month-calendar state store owned by the app service graph.
  private let nativeMonthCalendarStore: NativeMonthCalendarStore
  /// Upcoming-calendar state store owned by the app service graph.
  private let nativeUpcomingCalendarStore: NativeUpcomingCalendarStore
  /// Month-calendar agent client owned by the app service graph.
  private let monthCalendarAgentClient: MonthCalendarAgentClient
  /// Upcoming-calendar agent client owned by the app service graph.
  private let upcomingCalendarAgentClient: UpcomingCalendarAgentClient
  /// Network-agent client owned by the app service graph.
  private let networkAgentClient: NetworkAgentClient

  /// Creates a state provider from app-owned stores and clients.
  init(
    nativeWiFiStore: NativeWiFiStore,
    nativeMonthCalendarStore: NativeMonthCalendarStore,
    nativeUpcomingCalendarStore: NativeUpcomingCalendarStore,
    monthCalendarAgentClient: MonthCalendarAgentClient,
    upcomingCalendarAgentClient: UpcomingCalendarAgentClient,
    networkAgentClient: NetworkAgentClient
  ) {
    self.nativeWiFiStore = nativeWiFiStore
    self.nativeMonthCalendarStore = nativeMonthCalendarStore
    self.nativeUpcomingCalendarStore = nativeUpcomingCalendarStore
    self.monthCalendarAgentClient = monthCalendarAgentClient
    self.upcomingCalendarAgentClient = upcomingCalendarAgentClient
    self.networkAgentClient = networkAgentClient
  }

  /// Whether any calendar-agent client is currently connected.
  var calendarAgentConnected: Bool {
    return upcomingCalendarAgentClient.isConnected || monthCalendarAgentClient.isConnected
  }

  /// Whether the network-agent client is currently connected.
  var networkAgentConnected: Bool {
    return networkAgentClient.isConnected
  }

  /// Human-readable calendar permission state.
  var calendarPermissionLabel: String {
    let upcoming = nativeUpcomingCalendarStore.snapshot?.permissionState
    let month = nativeMonthCalendarStore.snapshot?.permissionState

    if let upcoming, upcoming != "unknown" {
      return upcoming
    }

    if let month, month != "unknown" {
      return month
    }

    return upcoming ?? month ?? "unknown"
  }

  /// Human-readable Wi-Fi/location permission state.
  var wifiPermissionLabel: String {
    return nativeWiFiStore.snapshot?.permissionState ?? "unknown"
  }
}
