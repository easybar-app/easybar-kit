import Foundation

extension CalendarBuiltinConfig {
  public struct Month: Sendable {
    public struct Popup: Sendable {
      public struct Style: Sendable {
        public var backgroundColorHex: String
        public var borderColorHex: String
        public var borderWidth: Double
        public var cornerRadius: Double
        public var paddingX: Double
        public var paddingY: Double
        public var spacing: Double
        public var marginX: Double
        public var marginY: Double

        public init(
          backgroundColorHex: String,
          borderColorHex: String,
          borderWidth: Double,
          cornerRadius: Double,
          paddingX: Double,
          paddingY: Double,
          spacing: Double,
          marginX: Double,
          marginY: Double
        ) {
          self.backgroundColorHex = backgroundColorHex
          self.borderColorHex = borderColorHex
          self.borderWidth = borderWidth
          self.cornerRadius = cornerRadius
          self.paddingX = paddingX
          self.paddingY = paddingY
          self.spacing = spacing
          self.marginX = marginX
          self.marginY = marginY
        }
      }

      public struct CalendarStyle: Sendable {
        public var showWeekNumbers: Bool
        public var showEventIndicators: Bool
        public var headerTextColorHex: String
        public var weekdayTextColorHex: String
        public var firstWeekday: Int?
        public var weekdayFormat: String
        public var weekdaySymbols: [String]?
        public var resolvedWeekdaySymbols: [String]
        public var dayTextColorHex: String
        public var outsideMonthTextColorHex: String
        public var todayCellBackgroundColorHex: String
        public var todayCellBorderColorHex: String
        public var todayCellBorderWidth: Double
        public var todayMarkerVariant: CalendarTodayMarkerVariant
        public var todayMarkerSize: Double
        public var indicatorColorHex: String

        public init(
          showWeekNumbers: Bool,
          showEventIndicators: Bool,
          headerTextColorHex: String,
          weekdayTextColorHex: String,
          firstWeekday: Int?,
          weekdayFormat: String,
          weekdaySymbols: [String]?,
          resolvedWeekdaySymbols: [String],
          dayTextColorHex: String,
          outsideMonthTextColorHex: String,
          todayCellBackgroundColorHex: String,
          todayCellBorderColorHex: String,
          todayCellBorderWidth: Double,
          todayMarkerVariant: CalendarTodayMarkerVariant,
          todayMarkerSize: Double,
          indicatorColorHex: String
        ) {
          self.showWeekNumbers = showWeekNumbers
          self.showEventIndicators = showEventIndicators
          self.headerTextColorHex = headerTextColorHex
          self.weekdayTextColorHex = weekdayTextColorHex
          self.firstWeekday = firstWeekday
          self.weekdayFormat = weekdayFormat
          self.weekdaySymbols = weekdaySymbols
          self.resolvedWeekdaySymbols = resolvedWeekdaySymbols
          self.dayTextColorHex = dayTextColorHex
          self.outsideMonthTextColorHex = outsideMonthTextColorHex
          self.todayCellBackgroundColorHex = todayCellBackgroundColorHex
          self.todayCellBorderColorHex = todayCellBorderColorHex
          self.todayCellBorderWidth = todayCellBorderWidth
          self.todayMarkerVariant = todayMarkerVariant
          self.todayMarkerSize = todayMarkerSize
          self.indicatorColorHex = indicatorColorHex
        }
      }

      public struct SelectionStyle: Sendable {
        public var selectedTextColorHex: String
        public var selectedBackgroundColorHex: String
        public var selectionDateFormat: String
        public var selectionDateSeparator: String
        public var allowsRangeSelection: Bool
        public var resetSelectionOnThirdTap: Bool

        public init(
          selectedTextColorHex: String,
          selectedBackgroundColorHex: String,
          selectionDateFormat: String,
          selectionDateSeparator: String,
          allowsRangeSelection: Bool,
          resetSelectionOnThirdTap: Bool
        ) {
          self.selectedTextColorHex = selectedTextColorHex
          self.selectedBackgroundColorHex = selectedBackgroundColorHex
          self.selectionDateFormat = selectionDateFormat
          self.selectionDateSeparator = selectionDateSeparator
          self.allowsRangeSelection = allowsRangeSelection
          self.resetSelectionOnThirdTap = resetSelectionOnThirdTap
        }
      }

      public struct AgendaStyle: Sendable {
        public var layout: MonthCalendarPopupLayout
        public var appointmentsScrollable: Bool
        public var appointmentsMinHeight: Double
        public var appointmentsMaxHeight: Double
        public var agendaTitle: String
        public var maxVisibleAppointments: Int

        public init(
          layout: MonthCalendarPopupLayout,
          appointmentsScrollable: Bool,
          appointmentsMinHeight: Double,
          appointmentsMaxHeight: Double,
          agendaTitle: String,
          maxVisibleAppointments: Int
        ) {
          self.layout = layout
          self.appointmentsScrollable = appointmentsScrollable
          self.appointmentsMinHeight = appointmentsMinHeight
          self.appointmentsMaxHeight = appointmentsMaxHeight
          self.agendaTitle = agendaTitle
          self.maxVisibleAppointments = maxVisibleAppointments
        }
      }

      public struct AnchorStyle: Sendable {
        public var dateFormat: String
        public var textColorHex: String?
        public var showDateText: Bool

        public init(dateFormat: String, textColorHex: String?, showDateText: Bool) {
          self.dateFormat = dateFormat
          self.textColorHex = textColorHex
          self.showDateText = showDateText
        }
      }

      public struct TodayButtonStyle: Sendable {
        public var title: String
        public var icon: String
        public var paddingX: Double
        public var paddingY: Double
        public var marginX: Double
        public var marginY: Double

        public init(
          title: String,
          icon: String,
          paddingX: Double,
          paddingY: Double,
          marginX: Double,
          marginY: Double
        ) {
          self.title = title
          self.icon = icon
          self.paddingX = paddingX
          self.paddingY = paddingY
          self.marginX = marginX
          self.marginY = marginY
        }
      }

      public var style: Style
      public var calendar: CalendarStyle
      public var selection: SelectionStyle
      public var agenda: AgendaStyle
      public var anchor: AnchorStyle
      public var todayButton: TodayButtonStyle

      public init(
        style: Style,
        calendar: CalendarStyle,
        selection: SelectionStyle,
        agenda: AgendaStyle,
        anchor: AnchorStyle,
        todayButton: TodayButtonStyle
      ) {
        self.style = style
        self.calendar = calendar
        self.selection = selection
        self.agenda = agenda
        self.anchor = anchor
        self.todayButton = todayButton
      }

      public var backgroundColorHex: String {
        get { style.backgroundColorHex }
        set { style.backgroundColorHex = newValue }
      }

      public var borderColorHex: String {
        get { style.borderColorHex }
        set { style.borderColorHex = newValue }
      }

      public var borderWidth: Double {
        get { style.borderWidth }
        set { style.borderWidth = newValue }
      }

      public var cornerRadius: Double {
        get { style.cornerRadius }
        set { style.cornerRadius = newValue }
      }

      public var paddingX: Double {
        get { style.paddingX }
        set { style.paddingX = newValue }
      }

      public var paddingY: Double {
        get { style.paddingY }
        set { style.paddingY = newValue }
      }

      public var spacing: Double {
        get { style.spacing }
        set { style.spacing = newValue }
      }

      public var marginX: Double {
        get { style.marginX }
        set { style.marginX = newValue }
      }

      public var marginY: Double {
        get { style.marginY }
        set { style.marginY = newValue }
      }

      public var showWeekNumbers: Bool {
        get { calendar.showWeekNumbers }
        set { calendar.showWeekNumbers = newValue }
      }

      public var showEventIndicators: Bool {
        get { calendar.showEventIndicators }
        set { calendar.showEventIndicators = newValue }
      }

      public var headerTextColorHex: String {
        get { calendar.headerTextColorHex }
        set { calendar.headerTextColorHex = newValue }
      }

      public var weekdayTextColorHex: String {
        get { calendar.weekdayTextColorHex }
        set { calendar.weekdayTextColorHex = newValue }
      }

      public var firstWeekday: Int? {
        get { calendar.firstWeekday }
        set { calendar.firstWeekday = newValue }
      }

      public var weekdayFormat: String {
        get { calendar.weekdayFormat }
        set { calendar.weekdayFormat = newValue }
      }

      public var weekdaySymbols: [String]? {
        get { calendar.weekdaySymbols }
        set { calendar.weekdaySymbols = newValue }
      }

      public var resolvedWeekdaySymbols: [String] {
        get { calendar.resolvedWeekdaySymbols }
        set { calendar.resolvedWeekdaySymbols = newValue }
      }

      public var dayTextColorHex: String {
        get { calendar.dayTextColorHex }
        set { calendar.dayTextColorHex = newValue }
      }

      public var outsideMonthTextColorHex: String {
        get { calendar.outsideMonthTextColorHex }
        set { calendar.outsideMonthTextColorHex = newValue }
      }

      public var todayCellBackgroundColorHex: String {
        get { calendar.todayCellBackgroundColorHex }
        set { calendar.todayCellBackgroundColorHex = newValue }
      }

      public var todayCellBorderColorHex: String {
        get { calendar.todayCellBorderColorHex }
        set { calendar.todayCellBorderColorHex = newValue }
      }

      public var todayCellBorderWidth: Double {
        get { calendar.todayCellBorderWidth }
        set { calendar.todayCellBorderWidth = newValue }
      }

      public var todayMarkerVariant: CalendarTodayMarkerVariant {
        get { calendar.todayMarkerVariant }
        set { calendar.todayMarkerVariant = newValue }
      }

      public var todayMarkerSize: Double {
        get { calendar.todayMarkerSize }
        set { calendar.todayMarkerSize = newValue }
      }

      public var indicatorColorHex: String {
        get { calendar.indicatorColorHex }
        set { calendar.indicatorColorHex = newValue }
      }

      public var selectedTextColorHex: String {
        get { selection.selectedTextColorHex }
        set { selection.selectedTextColorHex = newValue }
      }

      public var selectedBackgroundColorHex: String {
        get { selection.selectedBackgroundColorHex }
        set { selection.selectedBackgroundColorHex = newValue }
      }

      public var selectionDateFormat: String {
        get { selection.selectionDateFormat }
        set { selection.selectionDateFormat = newValue }
      }

      public var selectionDateSeparator: String {
        get { selection.selectionDateSeparator }
        set { selection.selectionDateSeparator = newValue }
      }

      public var allowsRangeSelection: Bool {
        get { selection.allowsRangeSelection }
        set { selection.allowsRangeSelection = newValue }
      }

      public var resetSelectionOnThirdTap: Bool {
        get { selection.resetSelectionOnThirdTap }
        set { selection.resetSelectionOnThirdTap = newValue }
      }

      public var layout: MonthCalendarPopupLayout {
        get { agenda.layout }
        set { agenda.layout = newValue }
      }

      public var appointmentsScrollable: Bool {
        get { agenda.appointmentsScrollable }
        set { agenda.appointmentsScrollable = newValue }
      }

      public var appointmentsMinHeight: Double {
        get { agenda.appointmentsMinHeight }
        set { agenda.appointmentsMinHeight = newValue }
      }

      public var appointmentsMaxHeight: Double {
        get { agenda.appointmentsMaxHeight }
        set { agenda.appointmentsMaxHeight = newValue }
      }

      public var agendaTitle: String {
        get { agenda.agendaTitle }
        set { agenda.agendaTitle = newValue }
      }

      public var maxVisibleAppointments: Int {
        get { agenda.maxVisibleAppointments }
        set { agenda.maxVisibleAppointments = newValue }
      }

      public var todayButtonTitle: String {
        get { todayButton.title }
        set { todayButton.title = newValue }
      }

      public var todayButtonIcon: String {
        get { todayButton.icon }
        set { todayButton.icon = newValue }
      }

      public var todayButtonPaddingX: Double {
        get { todayButton.paddingX }
        set { todayButton.paddingX = newValue }
      }

      public var todayButtonPaddingY: Double {
        get { todayButton.paddingY }
        set { todayButton.paddingY = newValue }
      }

      public var todayButtonMarginX: Double {
        get { todayButton.marginX }
        set { todayButton.marginX = newValue }
      }

      public var todayButtonMarginY: Double {
        get { todayButton.marginY }
        set { todayButton.marginY = newValue }
      }
    }

    public var popup: Popup

    public init(popup: Popup) {
      self.popup = popup
    }
  }
}
