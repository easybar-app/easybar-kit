import Combine
import EasyBarCalendarPresentation
import EasyBarShared
import Foundation

/// View model for creating, editing, and deleting calendar events through injected actions.
@MainActor
public final class CalendarEventComposer: ObservableObject {
  /// Stable picker item describing one writable calendar.
  public struct CalendarOption: Identifiable, Equatable {
    /// Stable calendar identifier.
    public let id: String

    /// Human-readable calendar title.
    public let title: String

    /// Creates one selectable calendar option.
    public init(id: String, title: String) {
      self.id = id
      self.title = title
    }
  }

  /// Mutable row backing one alert selection entry.
  public struct AlertRow: Identifiable, Equatable {
    /// Stable row identifier for SwiftUI diffing.
    public let id: UUID

    /// Selected alert preset.
    public var option: AlertOption

    /// Custom alert lead time in minutes when `option == .custom`.
    public var customMinutesText: String

    /// Creates one alert row.
    public init(id: UUID = UUID(), option: AlertOption, customMinutesText: String = "") {
      self.id = id
      self.option = option
      self.customMinutesText = customMinutesText
    }
  }

  /// Composer mode.
  public enum Mode: Equatable {
    case create
    case edit(eventIdentifier: String)
  }

  @Published public internal(set) var mode: Mode = .create
  @Published public var title = ""
  @Published public var location = ""
  @Published public var selectedCalendarID = ""
  @Published public var startDate = Date()
  @Published public var endDate = Date()
  @Published public var isAllDay = false
  @Published public var selectedTravelTime: TravelTimeOption = .none
  @Published public var customTravelMinutesText = ""
  @Published public var alertRows: [AlertRow] = []
  @Published public internal(set) var calendarOptions: [CalendarOption] = []
  @Published public internal(set) var errorMessage: String?
  @Published public internal(set) var infoMessage: String?
  @Published public internal(set) var isSaving = false
  @Published public internal(set) var accessGranted = true

  let calendar = Calendar.current
  let config: CalendarComposerConfig
  let refreshSnapshots: () -> Void
  let createEventAction: (CalendarAgentCreateEvent, @escaping @MainActor @Sendable (Bool, String?) -> Void) -> Void
  let updateEventAction: (CalendarAgentUpdateEvent, @escaping @MainActor @Sendable (Bool, String?) -> Void) -> Void
  let deleteEventAction: (CalendarAgentDeleteEvent, @escaping @MainActor @Sendable (Bool, String?) -> Void) -> Void
  let openCalendarAppAction: () -> Void
  private var cancellables: Set<AnyCancellable> = []
  var preferredCalendarID: String?
  var preferredCalendarName: String?
  private var cleanFormState: CalendarEventComposerFormState?

  public init(
    config: CalendarComposerConfig,
    snapshotPublisher: AnyPublisher<CalendarAgentSnapshot?, Never>,
    refreshSnapshots: @escaping () -> Void,
    createEvent:
      @escaping (
        CalendarAgentCreateEvent, @escaping @MainActor @Sendable (Bool, String?) -> Void
      ) -> Void,
    updateEvent:
      @escaping (
        CalendarAgentUpdateEvent, @escaping @MainActor @Sendable (Bool, String?) -> Void
      ) -> Void,
    deleteEvent:
      @escaping (
        CalendarAgentDeleteEvent, @escaping @MainActor @Sendable (Bool, String?) -> Void
      ) -> Void,
    openCalendarApp: @escaping () -> Void
  ) {
    self.config = config
    self.refreshSnapshots = refreshSnapshots
    self.createEventAction = createEvent
    self.updateEventAction = updateEvent
    self.deleteEventAction = deleteEvent
    self.openCalendarAppAction = openCalendarApp

    snapshotPublisher
      .receive(on: RunLoop.main)
      .sink { [weak self] snapshot in
        self?.applySnapshot(snapshot)
      }
      .store(in: &cancellables)

    reset(using: Date())
    markFormClean()
  }

  /// Returns whether the current form contents can be saved.
  public var canSave: Bool {
    accessGranted
      && !isSaving
      && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !selectedCalendarID.isEmpty
  }

  /// Returns whether the currently loaded event can be deleted.
  public var canDelete: Bool {
    guard case .edit = mode else { return false }
    return accessGranted && !isSaving
  }

  /// Returns whether editable form values differ from the prepared event or defaults.
  public var hasUnsavedChanges: Bool {
    guard let cleanFormState else { return false }
    return !CalendarEventComposerFormState(composer: self).matches(cleanFormState)
  }

  /// Returns the current panel title.
  public var panelTitle: String {
    switch mode {
    case .create:
      return config.createTitle
    case .edit:
      return config.editTitle
    }
  }

  /// Returns the available alert options.
  public var alertOptions: [AlertOption] {
    AlertOption.allCases
  }

  /// Returns the available travel-time options.
  public var travelTimeOptions: [TravelTimeOption] {
    TravelTimeOption.allCases
  }

  /// Returns a localized or configured label for an alert option.
  public func alertLabel(for option: AlertOption) -> String {
    option.title(config: config)
  }

  /// Returns a localized or configured label for a travel-time option.
  public func travelTimeLabel(for option: TravelTimeOption) -> String {
    option.title(config: config)
  }

  /// Adds one new alert row.
  public func addAlertRow() {
    alertRows.append(AlertRow(option: .tenMinutes))
  }

  /// Removes one alert row.
  public func removeAlertRow(id: UUID) {
    guard alertRows.count > 1 else {
      alertRows = [AlertRow(option: .none)]
      return
    }

    alertRows.removeAll { $0.id == id }
  }

  /// Records the current editable values as the clean dismissal baseline.
  func markFormClean() {
    cleanFormState = CalendarEventComposerFormState(composer: self)
  }
}
