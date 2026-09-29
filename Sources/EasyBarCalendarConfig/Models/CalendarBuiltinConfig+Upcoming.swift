import Foundation

extension CalendarBuiltinConfig {
  /// Stores upcoming data.
  public struct Upcoming: Sendable {
    /// Stores events data.
    public struct Events: Sendable {
      /// The days for this events.
      public var days: Int
      /// Whether this events excludes past events.
      public var excludePastEvents: Bool

      /// Creates the events configuration.
      public init(days: Int, excludePastEvents: Bool) {
        self.days = days
        self.excludePastEvents = excludePastEvents
      }
    }

    /// Stores popup data.
    public struct Popup: Sendable {
      /// The background color hex for this popup.
      public var backgroundColorHex: String
      /// The border color hex for this popup.
      public var borderColorHex: String
      /// The border width for this popup.
      public var borderWidth: Double
      /// The corner radius for this popup.
      public var cornerRadius: Double
      /// The padding x for this popup.
      public var paddingX: Double
      /// The padding y for this popup.
      public var paddingY: Double
      /// The spacing for this popup.
      public var spacing: Double
      /// The margin x for this popup.
      public var marginX: Double
      /// The margin y for this popup.
      public var marginY: Double

      /// Creates a popup.
      public init(
        backgroundColorHex: String,
        borderColorHex: String,
        borderWidth: Double,
        cornerRadius: Double,
        paddingX: Double,
        paddingY: Double,
        spacing: Double,
        marginX: Double,
        marginY: Double
      ) {
        self.backgroundColorHex = backgroundColorHex
        self.borderColorHex = borderColorHex
        self.borderWidth = borderWidth
        self.cornerRadius = cornerRadius
        self.paddingX = paddingX
        self.paddingY = paddingY
        self.spacing = spacing
        self.marginX = marginX
        self.marginY = marginY
      }
    }

    /// The events for this upcoming.
    public var events: Events
    /// The popup for this upcoming.
    public var popup: Popup

    /// Creates the upcoming configuration.
    public init(events: Events, popup: Popup) {
      self.events = events
      self.popup = popup
    }
  }
}
