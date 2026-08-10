import EasyBarCalendarConfig
import EasyBarCalendarPresentation
import Foundation

extension CalendarBuiltinConfig {
  var presentationFilters: CalendarRequestFilters {
    CalendarRequestFilters(
      includedCalendarNames: filters.includedCalendarNames,
      excludedCalendarNames: filters.excludedCalendarNames,
      includedCalendarIDs: filters.includedCalendarIDs,
      excludedCalendarIDs: filters.excludedCalendarIDs,
      includedCalendarSourceIDs: filters.includedCalendarSourceIDs,
      excludedCalendarSourceIDs: filters.excludedCalendarSourceIDs
    )
  }

  var presentationBirthdays: CalendarBirthdayRequestOptions {
    CalendarBirthdayRequestOptions(
      showBirthdays: birthdays.showBirthdays,
      showAge: birthdays.birthdaysShowAge
    )
  }

  var presentationUpcomingRequestOptions: CalendarUpcomingRequestOptions {
    CalendarUpcomingRequestOptions(
      dayCount: upcoming.events.days,
      emptyText: appointments.emptyText,
      allDayLabel: appointments.allDayLabel,
      birthdays: presentationBirthdays,
      filters: presentationFilters
    )
  }

  var presentationMonthRequestOptions: CalendarMonthRequestOptions {
    CalendarMonthRequestOptions(
      emptyText: appointments.emptyText,
      allDayLabel: appointments.allDayLabel,
      birthdays: presentationBirthdays,
      filters: presentationFilters
    )
  }
}
