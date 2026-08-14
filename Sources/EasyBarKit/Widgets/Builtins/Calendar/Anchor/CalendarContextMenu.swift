import EasyBarCalendarConfig
import EasyBarShared
import Foundation

/// Persistent actions exposed by the native calendar context menu.
enum CalendarContextMenuAction: Equatable {
  case setPopupMode(CalendarPopupMode)
  case setAnchorLayout(CalendarAnchorLayout)
  case toggleAnchorField(CalendarAnchorFieldKind)
  case setTodayMarkerVariant(CalendarTodayMarkerVariant)
  case setTodayMarkerSize(Int)
  case toggleAppointmentOption(String)
  case toggleBirthdayOption(String)
  case refresh
  case openCalendarSettings

  static let allowedTodayMarkerSizes = [18, 20, 22, 24, 26, 28]
  static let customTodayMarkerSizeID = "calendar.today_marker.size.custom"

  init?(id: String) {
    if let value = id.removingPrefix("calendar.popup."),
      let mode = CalendarPopupMode(rawValue: value)
    {
      self = .setPopupMode(mode)
      return
    }
    if let value = id.removingPrefix("calendar.layout."),
      let layout = CalendarAnchorLayout(rawValue: value)
    {
      self = .setAnchorLayout(layout)
      return
    }
    if let value = id.removingPrefix("calendar.anchor_field."),
      let field = CalendarAnchorFieldKind(rawValue: value)
    {
      self = .toggleAnchorField(field)
      return
    }
    if let value = id.removingPrefix("calendar.today_marker.variant."),
      let variant = CalendarTodayMarkerVariant(rawValue: value)
    {
      self = .setTodayMarkerVariant(variant)
      return
    }
    if let value = id.removingPrefix("calendar.today_marker.size."),
      let size = Int(value),
      Self.allowedTodayMarkerSizes.contains(size)
    {
      self = .setTodayMarkerSize(size)
      return
    }
    if let option = id.removingPrefix("calendar.appointment."),
      appointmentOptions.contains(where: { $0.id == option })
    {
      self = .toggleAppointmentOption(option)
      return
    }
    if let option = id.removingPrefix("calendar.birthday."),
      birthdayOptions.contains(where: { $0.id == option })
    {
      self = .toggleBirthdayOption(option)
      return
    }

    switch id {
    case "calendar.refresh": self = .refresh
    case "calendar.open_settings": self = .openCalendarSettings
    default: return nil
    }
  }
}

/// Builds the calendar menu from its effective session configuration.
enum CalendarContextMenu {
  static func make(config: Config.CalendarBuiltinConfig) -> [WidgetContextMenuItem] {
    let popupModes = CalendarPopupMode.allCases.map { mode in
      WidgetContextMenuItem(
        id: "calendar.popup.\(mode.rawValue)",
        title: popupModeTitle(mode),
        checked: config.popupMode == mode
      )
    }
    let layouts = CalendarAnchorLayout.allCases.map { layout in
      WidgetContextMenuItem(
        id: "calendar.layout.\(layout.rawValue)",
        title: layout.rawValue.capitalized,
        checked: config.anchor.layout == layout
      )
    }
    let anchorFields = CalendarAnchorFieldKind.allCases.map { field in
      let selected = config.anchor.fields.contains(field)
      return WidgetContextMenuItem(
        id: "calendar.anchor_field.\(field.rawValue)",
        title: field.rawValue.capitalized,
        enabled: !selected || config.anchor.fields.count > 1,
        checked: selected
      )
    }
    let todayMarkerVariants = CalendarTodayMarkerVariant.allCases.map { variant in
      WidgetContextMenuItem(
        id: "calendar.today_marker.variant.\(variant.rawValue)",
        title: todayMarkerTitle(variant),
        checked: config.month.popup.calendar.todayMarkerVariant == variant
      )
    }
    var todayMarkerSizes = CalendarContextMenuAction.allowedTodayMarkerSizes.map { size in
      WidgetContextMenuItem(
        id: "calendar.today_marker.size.\(size)",
        title: "\(size) pt",
        checked: config.month.popup.calendar.todayMarkerSize == Double(size)
      )
    }
    if !CalendarContextMenuAction.allowedTodayMarkerSizes.contains(where: {
      config.month.popup.calendar.todayMarkerSize == Double($0)
    }) {
      todayMarkerSizes.insert(
        WidgetContextMenuItem(
          id: CalendarContextMenuAction.customTodayMarkerSizeID,
          title: "Custom: \(formattedMarkerSize(config.month.popup.calendar.todayMarkerSize)) pt",
          enabled: false,
          checked: true
        ),
        at: 0
      )
    }
    let todayItems = [
      WidgetContextMenuItem(title: "Marker Style", submenu: todayMarkerVariants),
      WidgetContextMenuItem(title: "Marker Size", submenu: todayMarkerSizes),
    ]

    return [
      WidgetContextMenuItem(title: "Popup", submenu: popupModes),
      WidgetContextMenuItem(title: "Anchor Layout", submenu: layouts),
      WidgetContextMenuItem(title: "Anchor Fields", submenu: anchorFields),
      WidgetContextMenuItem(title: "Today", submenu: todayItems),
      WidgetContextMenuItem(
        title: "Appointment Details",
        submenu: appointmentMenu(config.appointments)
      ),
      WidgetContextMenuItem(
        title: "Birthdays",
        submenu: birthdayMenu(config.birthdays)
      ),
      WidgetContextMenuItem(separator: true),
      WidgetContextMenuItem(id: "calendar.refresh", title: "Refresh"),
      WidgetContextMenuItem(id: "calendar.open_settings", title: "Open Calendar Settings"),
    ]
  }

  private static func popupModeTitle(_ mode: CalendarPopupMode) -> String {
    switch mode {
    case .none: "None"
    case .upcoming: "Upcoming"
    case .month: "Month"
    }
  }

  private static func todayMarkerTitle(_ variant: CalendarTodayMarkerVariant) -> String {
    switch variant {
    case .regularRoundedRectangle: "Rounded Rectangle"
    case .softWobble: "Soft Wobble"
    case .doubleSketch: "Double Sketch"
    case .openLoop: "Open Loop"
    }
  }

  private static func formattedMarkerSize(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0...2)))
  }

  private static func appointmentMenu(
    _ appointments: CalendarBuiltinConfig.Appointments
  ) -> [WidgetContextMenuItem] {
    appointmentOptions.map { option in
      WidgetContextMenuItem(
        id: "calendar.appointment.\(option.id)",
        title: option.title,
        checked: option.value(appointments)
      )
    }
  }

  private static func birthdayMenu(
    _ birthdays: CalendarBuiltinConfig.Birthdays
  ) -> [WidgetContextMenuItem] {
    birthdayOptions.map { option in
      WidgetContextMenuItem(
        id: "calendar.birthday.\(option.id)",
        title: option.title,
        enabled: option.id != "show_age" || birthdays.showBirthdays,
        checked: option.value(birthdays)
      )
    }
  }
}

struct CalendarAppointmentMenuOption {
  let id: String
  let title: String
  let configKey: String
  let keyPath: WritableKeyPath<CalendarBuiltinConfig.Appointments, Bool>

  func value(_ appointments: CalendarBuiltinConfig.Appointments) -> Bool {
    appointments[keyPath: keyPath]
  }
}

struct CalendarBirthdayMenuOption {
  let id: String
  let title: String
  let configKey: String
  let keyPath: WritableKeyPath<CalendarBuiltinConfig.Birthdays, Bool>

  func value(_ birthdays: CalendarBuiltinConfig.Birthdays) -> Bool {
    birthdays[keyPath: keyPath]
  }
}

nonisolated(unsafe) let appointmentOptions: [CalendarAppointmentMenuOption] = [
  .init(
    id: "calendar_name", title: "Calendar Name", configKey: "show_calendar_name",
    keyPath: \.showCalendarName),
  .init(
    id: "all_day_label", title: "All-day Label", configKey: "show_all_day_label",
    keyPath: \.showAllDayLabel),
  .init(id: "location", title: "Location", configKey: "show_location", keyPath: \.showLocation),
  .init(
    id: "travel_time", title: "Travel Time", configKey: "show_travel_time",
    keyPath: \.showTravelTime),
  .init(id: "end_time", title: "End Time", configKey: "show_end_time", keyPath: \.showEndTime),
  .init(
    id: "alert_icon", title: "Alert Icon", configKey: "show_alert_icon",
    keyPath: \.showAlertIcon),
]

nonisolated(unsafe) let birthdayOptions: [CalendarBirthdayMenuOption] = [
  .init(
    id: "show_birthdays", title: "Show Birthdays", configKey: "show_birthdays",
    keyPath: \.showBirthdays),
  .init(
    id: "show_age", title: "Show Age", configKey: "birthdays_show_age",
    keyPath: \.birthdaysShowAge),
]

extension String {
  fileprivate func removingPrefix(_ prefix: String) -> String? {
    guard hasPrefix(prefix) else { return nil }
    let suffix = String(dropFirst(prefix.count))
    return suffix.isEmpty ? nil : suffix
  }
}
