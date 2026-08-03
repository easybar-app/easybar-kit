import EasyBarCalendarPresentation
import EasyBarShared
import Foundation

extension CalendarEventComposer {
  /// Saves the current form as a create or update mutation.
  public func save(onSuccess: @escaping () -> Void) {
    clearMessages()

    switch makeDraft() {
    case .failure(let message):
      errorMessage = message

    case .success(let draft):
      isSaving = true

      switch mode {
      case .create:
        createEventAction(makeCreateEvent(from: draft)) { [weak self] success, message in
          Task { @MainActor in
            self?.handleMutationResult(
              success: success,
              failureMessage: message,
              successMessage: "Appointment created.",
              onSuccess: onSuccess
            )
          }
        }

      case .edit(let eventIdentifier):
        updateEventAction(makeUpdateEvent(from: draft, eventIdentifier: eventIdentifier)) {
          [weak self] success, message in
          Task { @MainActor in
            self?.handleMutationResult(
              success: success,
              failureMessage: message,
              successMessage: "Appointment updated.",
              onSuccess: onSuccess
            )
          }
        }
      }
    }
  }

  /// Deletes the current event.
  public func delete(onSuccess: @escaping () -> Void) {
    clearMessages()

    guard case .edit(let eventIdentifier) = mode else {
      errorMessage = "No appointment is selected."
      return
    }

    isSaving = true

    deleteEventAction(CalendarAgentDeleteEvent(eventIdentifier: eventIdentifier)) { [weak self] success, message in
      Task { @MainActor in
        self?.handleMutationResult(
          success: success,
          failureMessage: message,
          successMessage: "Appointment removed.",
          onSuccess: onSuccess
        )
      }
    }
  }

  /// Opens Calendar.app.
  public func openCalendarApp() {
    openCalendarAppAction()
  }

  private func makeCreateEvent(from draft: Draft) -> CalendarAgentCreateEvent {
    CalendarAgentCreateEvent(
      title: draft.title,
      startDate: draft.startDate,
      endDate: draft.endDate,
      isAllDay: draft.isAllDay,
      calendarID: draft.calendarID,
      location: draft.location,
      alertOffsetsSeconds: draft.alertOffsetsSeconds,
      travelTimeSeconds: draft.travelTimeSeconds
    )
  }

  private func makeUpdateEvent(
    from draft: Draft,
    eventIdentifier: String
  ) -> CalendarAgentUpdateEvent {
    CalendarAgentUpdateEvent(
      eventIdentifier: eventIdentifier,
      title: draft.title,
      startDate: draft.startDate,
      endDate: draft.endDate,
      isAllDay: draft.isAllDay,
      calendarID: draft.calendarID,
      location: draft.location,
      alertOffsetsSeconds: draft.alertOffsetsSeconds,
      travelTimeSeconds: draft.travelTimeSeconds
    )
  }

  private func handleMutationResult(
    success: Bool,
    failureMessage: String?,
    successMessage: String,
    onSuccess: @escaping () -> Void
  ) {
    isSaving = false

    guard success else {
      errorMessage = "Failed: \(failureMessage ?? "unknown error")"
      return
    }

    infoMessage = successMessage
    markFormClean()
    refreshSnapshots()
    onSuccess()
  }
}
