import Foundation

extension IPC {
  /// Filters one live log subscription independently from persistent file logging.
  public struct LogSubscription: Codable, Equatable, Sendable {
    /// The widget for this log subscription.
    public let widget: String?
    /// The runtime for this log subscription.
    public let runtime: ProcessLogRuntime?
    /// The minimum level accepted by this log subscription.
    public let minimumLevel: ProcessLogLevel?
    /// The stable identifier for this log subscription.
    public let requestID: String?

    /// Maps stored properties to their encoded keys.
    private enum CodingKeys: String, CodingKey {
      case widget
      case runtime
      case minimumLevel = "minimum_level"
      case requestID = "request_id"
    }

    /// Creates one live log subscription. A nil level inherits the app logger level.
    public init(
      widget: String? = nil,
      runtime: ProcessLogRuntime? = nil,
      minimumLevel: ProcessLogLevel? = nil,
      requestID: String? = nil
    ) {
      self.widget = widget
      self.runtime = runtime
      self.minimumLevel = minimumLevel
      self.requestID = requestID
    }

    /// Resolves the minimum level used by this subscriber.
    public func effectiveMinimumLevel(default defaultLevel: ProcessLogLevel) -> ProcessLogLevel {
      minimumLevel ?? defaultLevel
    }

    /// Returns whether one event matches every subscription filter.
    public func matches(
      _ event: ProcessLogEvent,
      defaultMinimumLevel: ProcessLogLevel
    ) -> Bool {
      ProcessLogFilter(
        widget: widget,
        runtime: runtime,
        minimumLevel: effectiveMinimumLevel(default: defaultMinimumLevel),
        requestID: requestID
      ).matches(event.record)
    }
  }
}
