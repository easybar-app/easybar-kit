import EasyBarShared
import Foundation

public struct CalendarBuiltinConfig: Sendable {
  public struct Filters: Sendable {
    public var includedCalendarNames: [String]
    public var excludedCalendarNames: [String]
    public var includedCalendarSourceNames: [String]
    public var excludedCalendarSourceNames: [String]
    public var includedCalendarIDs: [String]
    public var excludedCalendarIDs: [String]
    public var includedCalendarSourceIDs: [String]
    public var excludedCalendarSourceIDs: [String]

    public init(
      includedCalendarNames: [String],
      excludedCalendarNames: [String],
      includedCalendarSourceNames: [String],
      excludedCalendarSourceNames: [String],
      includedCalendarIDs: [String],
      excludedCalendarIDs: [String],
      includedCalendarSourceIDs: [String],
      excludedCalendarSourceIDs: [String]
    ) {
      self.includedCalendarNames = includedCalendarNames
      self.excludedCalendarNames = excludedCalendarNames
      self.includedCalendarSourceNames = includedCalendarSourceNames
      self.excludedCalendarSourceNames = excludedCalendarSourceNames
      self.includedCalendarIDs = includedCalendarIDs
      self.excludedCalendarIDs = excludedCalendarIDs
      self.includedCalendarSourceIDs = includedCalendarSourceIDs
      self.excludedCalendarSourceIDs = excludedCalendarSourceIDs
    }
  }

  public struct Appointments: Sendable {
    public var itemIndent: Double
    public var eventTextColorHex: String
    public var emptyTextColorHex: String
    public var secondaryTextColorHex: String
    public var travelTextColorHex: String
    public var emptyText: String
    public var showCalendarName: Bool
    public var showAllDayLabel: Bool
    public var showHolidayAllDayLabel: Bool
    public var allDayLabel: String
    public var meetingURLPatterns: [String]
    public var showLocation: Bool
    public var locationIcon: String
    public var locationIconColorHex: String?
    public var showTravelTime: Bool
    public var showEndTime: Bool
    public var travelIcon: String
    public var travelIconColorHex: String?
    public var showAlertIcon: Bool
    public var alertIcon: String
    public var alertIconColorHex: String?

    public init(
      itemIndent: Double,
      eventTextColorHex: String,
      emptyTextColorHex: String,
      secondaryTextColorHex: String,
      travelTextColorHex: String,
      emptyText: String,
      showCalendarName: Bool,
      showAllDayLabel: Bool,
      showHolidayAllDayLabel: Bool,
      allDayLabel: String,
      meetingURLPatterns: [String],
      showLocation: Bool,
      locationIcon: String,
      locationIconColorHex: String?,
      showTravelTime: Bool,
      showEndTime: Bool,
      travelIcon: String,
      travelIconColorHex: String?,
      showAlertIcon: Bool,
      alertIcon: String,
      alertIconColorHex: String?
    ) {
      self.itemIndent = itemIndent
      self.eventTextColorHex = eventTextColorHex
      self.emptyTextColorHex = emptyTextColorHex
      self.secondaryTextColorHex = secondaryTextColorHex
      self.travelTextColorHex = travelTextColorHex
      self.emptyText = emptyText
      self.showCalendarName = showCalendarName
      self.showAllDayLabel = showAllDayLabel
      self.showHolidayAllDayLabel = showHolidayAllDayLabel
      self.allDayLabel = allDayLabel
      self.meetingURLPatterns = meetingURLPatterns
      self.showLocation = showLocation
      self.locationIcon = locationIcon
      self.locationIconColorHex = locationIconColorHex
      self.showTravelTime = showTravelTime
      self.showEndTime = showEndTime
      self.travelIcon = travelIcon
      self.travelIconColorHex = travelIconColorHex
      self.showAlertIcon = showAlertIcon
      self.alertIcon = alertIcon
      self.alertIconColorHex = alertIconColorHex
    }
  }

  public struct Birthdays: Sendable {
    public var showBirthdays: Bool
    public var birthdaysShowAge: Bool
    public var birthdayIcon: String
    public var birthdayIconColorHex: String?

    public init(
      showBirthdays: Bool,
      birthdaysShowAge: Bool,
      birthdayIcon: String,
      birthdayIconColorHex: String?
    ) {
      self.showBirthdays = showBirthdays
      self.birthdaysShowAge = birthdaysShowAge
      self.birthdayIcon = birthdayIcon
      self.birthdayIconColorHex = birthdayIconColorHex
    }
  }

  public struct Anchor: Sendable {
    public var layout: CalendarAnchorLayout
    public var fields: [CalendarAnchorFieldKind]
    public var spacing: Double
    public var separator: String
    public var time: Field
    public var date: Field

    public struct Field: Sendable {
      public var format: String
      public var textColorHex: String?
      public var fontFamily: String?
      public var fontSize: Double?
      public var fontWeight: CalendarAnchorFontWeight

      public init(
        format: String,
        textColorHex: String?,
        fontFamily: String?,
        fontSize: Double?,
        fontWeight: CalendarAnchorFontWeight
      ) {
        self.format = format
        self.textColorHex = textColorHex
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.fontWeight = fontWeight
      }
    }

    public init(
      layout: CalendarAnchorLayout,
      fields: [CalendarAnchorFieldKind],
      spacing: Double,
      separator: String,
      time: Field,
      date: Field
    ) {
      self.layout = layout
      self.fields = fields
      self.spacing = spacing
      self.separator = separator
      self.time = time
      self.date = date
    }

    public func field(_ kind: CalendarAnchorFieldKind) -> Field {
      switch kind {
      case .time: return time
      case .date: return date
      }
    }
  }

  public var placement: CalendarWidgetPlacement
  public var style: CalendarWidgetStyle
  public var popupMode: CalendarPopupMode
  public var anchor: Anchor
  public var filters: Filters
  public var appointments: Appointments
  public var birthdays: Birthdays
  public var composer: Composer
  public var upcoming: Upcoming
  public var month: Month

  public init(
    placement: CalendarWidgetPlacement,
    style: CalendarWidgetStyle,
    popupMode: CalendarPopupMode,
    anchor: Anchor,
    filters: Filters,
    appointments: Appointments,
    birthdays: Birthdays,
    composer: Composer,
    upcoming: Upcoming,
    month: Month
  ) {
    self.placement = placement
    self.style = style
    self.popupMode = popupMode
    self.anchor = anchor
    self.filters = filters
    self.appointments = appointments
    self.birthdays = birthdays
    self.composer = composer
    self.upcoming = upcoming
    self.month = month
  }

}
