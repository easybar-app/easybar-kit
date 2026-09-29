import EasyBarCalendarPresentation
import EasyBarShared
import SwiftUI

/// Renders the reusable month-calendar popup.
public struct CalendarMonthPopupView<Store: CalendarMonthPopupStore>: View {

  /// Stores day cell data.
  struct DayCell: Identifiable {
    /// The stable identifier for this day cell.
    let id: String
    /// The date for this day cell.
    let date: Date
    /// Whether this day cell is current month.
    let isCurrentMonth: Bool
  }

  /// Stores week row data.
  struct WeekRow: Identifiable {
    /// The stable identifier for this week row.
    let id: String
    /// The week start date for this week row.
    let weekStartDate: Date
    /// The week number for this week row.
    let weekNumber: Int
    /// The days for this week row.
    let days: [DayCell]
  }

  /// Stores day indicator segment data.
  struct DayIndicatorSegment: Identifiable {
    /// The stable identifier for this day indicator segment.
    let id: String
    /// The color hex for this day indicator segment.
    let colorHex: String
    /// The fraction for this day indicator segment.
    let fraction: CGFloat
  }

  typealias AgendaRow = CalendarAgendaBuilder.Entry

  @ObservedObject var store: Store
  /// The logger used to record operational diagnostics.
  let logger: ProcessLogger
  /// The config for this calendar month popup view.
  let config: CalendarMonthPopupConfig
  /// The appointments style for this calendar month popup view.
  let appointmentsStyle: CalendarAppointmentsStyle
  /// The birthdays for this calendar month popup view.
  let birthdays: CalendarBirthdayStyle
  /// The empty text for this calendar month popup view.
  let emptyText: String
  /// The event actions for this calendar month popup view.
  let eventActions: CalendarEventActions?
  /// The on visible month changed for this calendar month popup view.
  let onVisibleMonthChanged: (Date) -> Void
  /// The on create event for this calendar month popup view.
  let onCreateEvent: (Date, @escaping () -> Void) -> Void
  /// The on edit event for this calendar month popup view.
  let onEditEvent: (CalendarAgentEvent, @escaping () -> Void) -> Void
  /// The on refresh requested for this calendar month popup view.
  let onRefreshRequested: () -> Void
  /// The now provider for this calendar month popup view.
  let nowProvider: () -> Date
  /// The calendar for this calendar month popup view.
  let calendar = Calendar.current

  /// Creates a calendar month popup view.
  public init(
    store: Store,
    logger: ProcessLogger,
    config: CalendarMonthPopupConfig,
    appointmentsStyle: CalendarAppointmentsStyle,
    birthdays: CalendarBirthdayStyle,
    emptyText: String,
    eventActions: CalendarEventActions? = nil,
    onVisibleMonthChanged: @escaping (Date) -> Void,
    onCreateEvent: @escaping (Date, @escaping () -> Void) -> Void,
    onEditEvent: @escaping (CalendarAgentEvent, @escaping () -> Void) -> Void,
    onRefreshRequested: @escaping () -> Void,
    nowProvider: @escaping () -> Date = Date.init
  ) {
    self.store = store
    self.logger = logger
    self.config = config
    self.appointmentsStyle = appointmentsStyle
    self.birthdays = birthdays
    self.emptyText = emptyText
    self.eventActions = eventActions
    self.onVisibleMonthChanged = onVisibleMonthChanged
    self.onCreateEvent = onCreateEvent
    self.onEditEvent = onEditEvent
    self.onRefreshRequested = onRefreshRequested
    self.nowProvider = nowProvider

    let initialDate = nowProvider()
    _visibleMonth = State(initialValue: Self.startOfMonth(initialDate))
    _selectedStartDate = State(initialValue: initialDate)
    _selectedEndDate = State(initialValue: initialDate)
  }

  @State var visibleMonth: Date
  @State var selectedStartDate: Date
  @State var selectedEndDate: Date

  @State var isDragSelecting = false
  @State var dragAnchorDate: Date?
  @State var dragDidCrossIntoAnotherDay = false
  @State var lastResolvedDragDate: Date?

  @State var monthGridFrame: CGRect = .zero
  @State var dayCellFrames: [Date: CGRect] = [:]
  @State var isYearPickerPresented = false
  @State var yearPickerPageStart = 0
  @State var shouldAutoSelectVisibleMonthEvent = false

  /// Renders the month calendar popup.
  public var body: some View {
    ZStack {
      popupLayoutView

      if isYearPickerPresented {
        Button("Close year picker") {
          isYearPickerPresented = false
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .foregroundStyle(.clear)
        .background(Color.black.opacity(0.001))

        yearPickerOverlayView
      }
    }
    .frame(width: popupWidth, alignment: .leading)
    .padding(.horizontal, CGFloat(config.paddingX))
    .padding(.vertical, CGFloat(config.paddingY))
    .background {
      RoundedRectangle(cornerRadius: popupCornerRadius, style: .continuous)
        .fill(color(config.backgroundColorHex))
    }
    .overlay {
      RoundedRectangle(cornerRadius: popupCornerRadius, style: .continuous)
        .stroke(
          color(config.borderColorHex),
          lineWidth: max(CGFloat(config.borderWidth), 0)
        )
    }
    .clipShape(RoundedRectangle(cornerRadius: popupCornerRadius, style: .continuous))
    .contentShape(RoundedRectangle(cornerRadius: popupCornerRadius, style: .continuous))
    .padding(.horizontal, CGFloat(config.marginX))
    .padding(.vertical, CGFloat(config.marginY))
    .onAppear {
      syncSelectionIntoVisibleMonth()
      onVisibleMonthChanged(visibleMonth)
      logSelection("on_appear")
    }
    .onChange(of: visibleMonth) { _, newValue in
      onVisibleMonthChanged(newValue)
    }
    .onChange(of: selectedStartDate) { _, _ in
      logSelection("selected_start_changed")
      logResolvedAppointments("selected_start_changed")
    }
    .onChange(of: selectedEndDate) { _, _ in
      logSelection("selected_end_changed")
      logResolvedAppointments("selected_end_changed")
    }
    .onChange(of: store.snapshot?.generatedAt) { _, generatedAt in
      logger.debug(
        "month calendar popup snapshot changed",
        .field("generated_at", "\(generatedAt?.description ?? "nil")"),
      )
      resolveVisibleMonthAutoSelection()
      logResolvedAppointments("snapshot_changed")
    }
  }
}

// MARK: - Styling

extension CalendarMonthPopupView {
  /// Returns the configured popup corner radius.
  var popupCornerRadius: CGFloat {
    return max(CGFloat(config.cornerRadius), 0)
  }

  /// Returns the fixed popup width for the active layout.
  var popupWidth: CGFloat {
    return minimumPopupWidth
  }
}
