import Foundation

/// Delivery and buffering policy for one event name.
enum EventDeliveryPolicy {
  /// Hard buffer used for automatically configured must-deliver subscriptions.
  static let maximumBufferedMustDeliverEvents = 256

  /// Preserve every event in enqueue order.
  case mustDeliver
  /// Prefer the newest value when events arrive faster than consumers read.
  case coalescing

  /// Returns the policy for one event name.
  static func forEventName(_ eventName: String) -> EventDeliveryPolicy {
    switch eventName {
    case AppEvent.secondTick.rawValue,
      AppEvent.intervalTick.rawValue,
      AppEvent.captureDevicesChanged.rawValue,
      AppEvent.captureActivityChanged.rawValue,
      AppEvent.cameraActivityChanged.rawValue,
      AppEvent.microphoneActivityChanged.rawValue,
      WidgetEvent.mouseEntered.rawValue,
      WidgetEvent.mouseExited.rawValue,
      WidgetEvent.mouseScrolled.rawValue,
      WidgetEvent.sliderPreview.rawValue:
      return .coalescing
    default:
      return .mustDeliver
    }
  }

  /// Returns whether one event should be delivered only to matching widget observers.
  static func routesDirectlyToWidgets(_ eventName: String) -> Bool {
    return WidgetEvent(rawValue: eventName) != nil
  }

  /// Returns the default buffering policy for one filtered subscription set.
  ///
  /// Streams that include must-deliver events retain the oldest bounded sequence.
  /// Overflow terminates the stalled subscriber rather than silently losing an action.
  /// Callers that observe every event may still select an explicit contract through `subscribeAll`.
  static func defaultBufferingPolicy(
    for eventNames: Set<String>
  ) -> AsyncStream<EasyBarEventPayload>.Continuation.BufferingPolicy {
    guard !eventNames.isEmpty else {
      return .bufferingOldest(Self.maximumBufferedMustDeliverEvents)
    }

    let containsMustDeliverEvent = eventNames.contains { eventName in
      forEventName(eventName) == .mustDeliver
    }

    return containsMustDeliverEvent
      ? .bufferingOldest(Self.maximumBufferedMustDeliverEvents)
      : .bufferingNewest(1)
  }
}

/// Aggregated subscriber-buffer overflow for one event class.
struct EventBackpressureSample: Hashable, Sendable {
  let name: String
  let count: Int
  let coalesced: Bool
}
