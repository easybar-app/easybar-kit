import Foundation

extension IPC {
  /// Filters one live log subscription independently from persistent file logging.
  public struct LogSubscription: Codable, Equatable, Sendable {
    public let widget: String?
    public let runtime: ProcessLogRuntime?
    public let minimumLevel: ProcessLogLevel?
    public let requestID: String?

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
