import EasyBarCalendarPresentation
import EasyBarShared
import SwiftUI

/// Renders the reusable month-calendar popup.
public struct CalendarMonthPopupView<Store: CalendarMonthPopupStore>: View {

  struct DayCell: Identifiable {
    let id: String
    let date: Date
    let isCurrentMonth: Bool
  }

  struct WeekRow: Identifiable {
    let id: String
    let weekStartDate: Date
    let weekNumber: Int
    let days: [DayCell]
  }

  struct DayIndicatorSegment: Identifiable {
    let id: String
    let colorHex: String
    let fraction: CGFloat
  }

  typealias AgendaRow = CalendarAgendaBuilder.Entry

  @ObservedObject var store: Store
  let logger: ProcessLogger
  let config: CalendarMonthPopupConfig
  let appointmentsStyle: CalendarAppointmentsStyle
  let birthdays: CalendarBirthdayStyle
  let emptyText: String
  let eventActions: CalendarEventActions?
  let onVisibleMonthChanged: (Date) -> Void
  let onCreateEvent: (Date, @escaping () -> Void) -> Void
  let onEditEvent: (CalendarAgentEvent, @escaping () -> Void) -> Void
  let onRefreshRequested: () -> Void
  let nowProvider: () -> Date
  let calendar = Calendar.current

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
