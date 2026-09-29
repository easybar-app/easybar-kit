import EasyBarShared
import Foundation

/// Stores calendar builtin config data.
public struct CalendarBuiltinConfig: Sendable {
  /// Stores filters data.
  public struct Filters: Sendable {
    /// The included calendar names for this filters.
    public var includedCalendarNames: [String]
    /// The excluded calendar names for this filters.
    public var excludedCalendarNames: [String]
    /// The included calendar source names for this filters.
    public var includedCalendarSourceNames: [String]
    /// The excluded calendar source names for this filters.
    public var excludedCalendarSourceNames: [String]
    /// The included calendar IDs for this filters.
    public var includedCalendarIDs: [String]
    /// The excluded calendar IDs for this filters.
    public var excludedCalendarIDs: [String]
    /// The included calendar source IDs for this filters.
    public var includedCalendarSourceIDs: [String]
    /// The excluded calendar source IDs for this filters.
    public var excludedCalendarSourceIDs: [String]

    /// Creates the filters configuration.
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

  /// Stores appointments data.
  public struct Appointments: Sendable {
    /// The item indent for this appointments.
    public var itemIndent: Double
    /// The event text color hex for this appointments.
    public var eventTextColorHex: String
    /// The empty text color hex for this appointments.
    public var emptyTextColorHex: String
    /// The secondary text color hex for this appointments.
    public var secondaryTextColorHex: String
    /// The travel text color hex for this appointments.
    public var travelTextColorHex: String
    /// The empty text for this appointments.
    public var emptyText: String
    /// Whether this appointments shows calendar name.
    public var showCalendarName: Bool
    /// Whether this appointments shows all day label.
    public var showAllDayLabel: Bool
    /// Whether this appointments shows holiday all day label.
    public var showHolidayAllDayLabel: Bool
    /// The all day label for this appointments.
    public var allDayLabel: String
    /// The meeting URL patterns for this appointments.
    public var meetingURLPatterns: [String]
    /// Whether this appointments shows location.
    public var showLocation: Bool
    /// The location icon for this appointments.
    public var locationIcon: String
    /// The location icon color hex for this appointments.
    public var locationIconColorHex: String?
    /// Whether this appointments shows travel time.
    public var showTravelTime: Bool
    /// Whether this appointments shows end time.
    public var showEndTime: Bool
    /// The travel icon for this appointments.
    public var travelIcon: String
    /// The travel icon color hex for this appointments.
    public var travelIconColorHex: String?
    /// Whether this appointments shows alert icon.
    public var showAlertIcon: Bool
    /// The alert icon for this appointments.
    public var alertIcon: String
    /// The alert icon color hex for this appointments.
    public var alertIconColorHex: String?

    /// Creates the appointments configuration.
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

  /// Stores birthdays data.
  public struct Birthdays: Sendable {
    /// Whether this birthdays shows birthdays.
    public var showBirthdays: Bool
    /// Whether the birthdays show age option is enabled for this birthdays.
    public var birthdaysShowAge: Bool
    /// The birthday icon for this birthdays.
    public var birthdayIcon: String
    /// The birthday icon color hex for this birthdays.
    public var birthdayIconColorHex: String?

    /// Creates the birthdays configuration.
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

  /// Stores anchor data.
  public struct Anchor: Sendable {
    /// The layout for this anchor.
    public var layout: CalendarAnchorLayout
    /// The fields for this anchor.
    public var fields: [CalendarAnchorFieldKind]
    /// The spacing for this anchor.
    public var spacing: Double
    /// The separator for this anchor.
    public var separator: String
    /// The time for this anchor.
    public var time: Field
    /// The date for this anchor.
    public var date: Field

    /// Stores field data.
    public struct Field: Sendable {
      /// The format for this field.
      public var format: String
      /// The text color hex for this field.
      public var textColorHex: String?
      /// The font family for this field.
      public var fontFamily: String?
      /// The font size for this field.
      public var fontSize: Double?
      /// The font weight for this field.
      public var fontWeight: CalendarAnchorFontWeight

      /// Creates a field.
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

    /// Creates the anchor configuration.
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

    /// Returns the field.
    public func field(_ kind: CalendarAnchorFieldKind) -> Field {
      switch kind {
      case .time: return time
      case .date: return date
      }
    }
  }

  /// The placement for this calendar builtin config.
  public var placement: CalendarWidgetPlacement
  /// The style for this calendar builtin config.
  public var style: CalendarWidgetStyle
  /// The popup mode for this calendar builtin config.
  public var popupMode: CalendarPopupMode
  /// The anchor for this calendar builtin config.
  public var anchor: Anchor
  /// The filters for this calendar builtin config.
  public var filters: Filters
  /// The appointments for this calendar builtin config.
  public var appointments: Appointments
  /// The birthdays for this calendar builtin config.
  public var birthdays: Birthdays
  /// The composer for this calendar builtin config.
  public var composer: Composer
  /// The upcoming for this calendar builtin config.
  public var upcoming: Upcoming
  /// The month for this calendar builtin config.
  public var month: Month

  /// Creates a calendar builtin config.
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
