import EasyBarShared
import Foundation

extension CalendarBuiltinConfig {
  static func parseUpcoming(
    reader: Reader,
    fallback: CalendarBuiltinConfig.Upcoming
  ) throws -> CalendarBuiltinConfig.Upcoming {
    CalendarBuiltinConfig.Upcoming(
      events: try parseUpcomingEvents(
        reader: try reader.section("events"),
        fallback: fallback.events
      ),
      popup: try parseUpcomingPopup(
        reader: try reader.section("popup"),
        fallback: fallback.popup
      )
    )
  }

  private static func parseUpcomingEvents(
    reader: Reader,
    fallback: CalendarBuiltinConfig.Upcoming.Events
  ) throws -> CalendarBuiltinConfig.Upcoming.Events {
    CalendarBuiltinConfig.Upcoming.Events(
      days: try reader.int(
        "days",
        fallback: fallback.days,
        minimum: 1,
        maximum: CalendarAgentRequestLimits.maximumSectionDayCount
      ),
      excludePastEvents: try reader.bool(
        "exclude_past_events",
        fallback: fallback.excludePastEvents
      )
    )
  }

  private static func parseUpcomingPopup(
    reader: Reader,
    fallback: CalendarBuiltinConfig.Upcoming.Popup
  ) throws -> CalendarBuiltinConfig.Upcoming.Popup {
    CalendarBuiltinConfig.Upcoming.Popup(
      backgroundColorHex: try reader.string(
        "background_color", fallback: fallback.backgroundColorHex),
      borderColorHex: try reader.string("border_color", fallback: fallback.borderColorHex),
      borderWidth: try reader.double("border_width", fallback: fallback.borderWidth, minimum: 0),
      cornerRadius: try reader.double("corner_radius", fallback: fallback.cornerRadius, minimum: 0),
      paddingX: try reader.double("padding_x", fallback: fallback.paddingX, minimum: 0),
      paddingY: try reader.double("padding_y", fallback: fallback.paddingY, minimum: 0),
      spacing: try reader.double("spacing", fallback: fallback.spacing, minimum: 0),
      marginX: try reader.double("margin_x", fallback: fallback.marginX),
      marginY: try reader.double("margin_y", fallback: fallback.marginY)
    )
  }
}
