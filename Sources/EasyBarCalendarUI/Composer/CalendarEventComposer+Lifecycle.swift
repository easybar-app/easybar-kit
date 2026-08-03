import EasyBarShared
import Foundation

extension CalendarEventComposer {
  /// Prepares the composer for creating a new event.
  public func prepare(defaultDate: Date) {
    mode = .create
    preferredCalendarID = nil
    preferredCalendarName = normalizedOptionalText(config.defaultCalendarName)

    reset(using: defaultDate)
    clearMessages()
    markFormClean()
    refreshSnapshots()
  }

  /// Prepares the composer for editing an existing event.
  public func prepare(event: CalendarAgentEvent) {
    clearMessages()

    guard let eventIdentifier = event.eventIdentifier ?? resolvedEventIdentifier(from: event) else {
      mode = .create
      reset(using: event.startDate)
      errorMessage = "This appointment cannot be edited."
      markFormClean()
      refreshSnapshots()
      return
    }

    mode = .edit(eventIdentifier: eventIdentifier)
    title = event.title
    location = event.location ?? ""
    preferredCalendarID = event.calendarID
    preferredCalendarName = event.calendarName
    selectedCalendarID = event.calendarID ?? selectedCalendarID
    startDate = event.startDate
    endDate = displayedEndDate(for: event)
    isAllDay = event.isAllDay

    selectedTravelTime =
      travelOption(for: event.travelTimeSeconds)
      ?? (event.travelTimeSeconds == nil ? .none : .custom)

    customTravelMinutesText = customMinutesText(
      knownSeconds: selectedTravelTime.seconds,
      actualSeconds: event.travelTimeSeconds
    )

    alertRows = initialAlertRows(
      offsets: event.alertOffsetsSeconds,
      defaultAlert: config.defaultAlert
    )

    markFormClean()
    refreshSnapshots()
  }

  func applySnapshot(_ snapshot: CalendarAgentSnapshot?) {
    let wasClean = !hasUnsavedChanges
    defer {
      if wasClean {
        markFormClean()
      }
    }

    accessGranted = snapshot?.accessGranted ?? false

    let options =
      snapshot?
      .writableCalendars
      .map { CalendarOption(id: $0.id, title: $0.title) }
      ?? []

    calendarOptions = options

    guard !options.isEmpty else {
      selectedCalendarID = ""
      return
    }

    if let preferredCalendarID,
      options.contains(where: { $0.id == preferredCalendarID })
    {
      selectedCalendarID = preferredCalendarID
      return
    }

    if !selectedCalendarID.isEmpty,
      options.contains(where: { $0.id == selectedCalendarID })
    {
      return
    }

    if let preferredCalendarName,
      let match = options.first(where: {
        $0.title.localizedCaseInsensitiveCompare(preferredCalendarName) == .orderedSame
      })
    {
      selectedCalendarID = match.id
      return
    }

    selectedCalendarID = options[0].id
  }

  func reset(using date: Date) {
    let defaultStart = defaultStartTime(on: date)
    let defaultEnd = defaultEndTime(on: date)

    title = ""
    location = ""
    startDate = defaultStart
    endDate = defaultEnd
    isAllDay = false
    selectedTravelTime = TravelTimeOption.from(configValue: config.defaultTravelTime)
    customTravelMinutesText = defaultCustomMinutesText(for: selectedTravelTime)
    alertRows = [AlertRow(option: AlertOption.from(configValue: config.defaultAlert))]
    selectedCalendarID = resolvedInitialCalendarID()
  }

  func resolvedInitialCalendarID() -> String {
    if let preferredCalendarID,
      calendarOptions.contains(where: { $0.id == preferredCalendarID })
    {
      return preferredCalendarID
    }

    if let preferredCalendarName,
      let match = calendarOptions.first(where: {
        $0.title.localizedCaseInsensitiveCompare(preferredCalendarName) == .orderedSame
      })
    {
      return match.id
    }

    if !selectedCalendarID.isEmpty,
      calendarOptions.contains(where: { $0.id == selectedCalendarID })
    {
      return selectedCalendarID
    }

    return calendarOptions.first?.id ?? ""
  }
}
