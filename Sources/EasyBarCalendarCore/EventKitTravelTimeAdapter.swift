import CEasyBarEventKitBridge
import EasyBarShared
import Foundation

/// Narrow adapter for EventKit's non-public travel-time storage.
///
/// The Objective-C bridge catches KVC exceptions that Swift cannot catch. The
/// adapter additionally rejects unsupported objects and invalid durations.
enum EventKitTravelTimeAdapter {
  static func read(from object: NSObject) -> TimeInterval? {
    var seconds: Double = 0
    guard easybar_eventkit_read_travel_time(object, &seconds) else { return nil }
    guard
      seconds.isFinite,
      seconds > 0,
      seconds <= CalendarAgentRequestLimits.maximumTravelTime
    else {
      return nil
    }
    return seconds
  }

  @discardableResult
  static func write(_ seconds: TimeInterval?, to object: NSObject) -> Bool {
    let normalized = seconds ?? 0
    guard
      normalized.isFinite,
      normalized >= 0,
      normalized <= CalendarAgentRequestLimits.maximumTravelTime
    else {
      return false
    }

    return easybar_eventkit_write_travel_time(object, normalized)
  }
}
