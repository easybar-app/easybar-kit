import EasyBarShared
import Foundation

extension CalendarBuiltinConfig {
  /// Stores month data.
  public struct Month: Sendable {
    /// Stores popup data.
    public struct Popup: Sendable {
      /// Stores style data.
      public struct Style: Sendable {
        /// The background color hex for this style.
        public var backgroundColorHex: String
        /// The border color hex for this style.
        public var borderColorHex: String
        /// The border width for this style.
        public var borderWidth: Double
        /// The corner radius for this style.
        public var cornerRadius: Double
        /// The padding x for this style.
        public var paddingX: Double
        /// The padding y for this style.
        public var paddingY: Double
        /// The spacing for this style.
        public var spacing: Double
        /// The margin x for this style.
        public var marginX: Double
        /// The margin y for this style.
        public var marginY: Double

        /// Creates a style.
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

      /// Stores calendar style data.
      public struct CalendarStyle: Sendable {
        /// Whether this calendar style shows week numbers.
        public var showWeekNumbers: Bool
        /// Whether this calendar style shows event indicators.
        public var showEventIndicators: Bool
        /// The header text color hex for this calendar style.
        public var headerTextColorHex: String
        /// The weekday text color hex for this calendar style.
        public var weekdayTextColorHex: String
        /// The first weekday for this calendar style.
        public var firstWeekday: Int?
        /// The weekday format for this calendar style.
        public var weekdayFormat: String
        /// The weekday symbols for this calendar style.
        public var weekdaySymbols: [String]?
        /// The resolved weekday symbols for this calendar style.
        public var resolvedWeekdaySymbols: [String]
        /// The day text color hex for this calendar style.
        public var dayTextColorHex: String
        /// The outside month text color hex for this calendar style.
        public var outsideMonthTextColorHex: String
        /// The today cell background color hex for this calendar style.
        public var todayCellBackgroundColorHex: String
        /// The today cell border color hex for this calendar style.
        public var todayCellBorderColorHex: String
        /// The today cell border width for this calendar style.
        public var todayCellBorderWidth: Double
        /// The today marker variant for this calendar style.
        public var todayMarkerVariant: CalendarTodayMarkerVariant
        /// The today marker size for this calendar style.
        public var todayMarkerSize: Double
        /// The indicator color hex for this calendar style.
        public var indicatorColorHex: String

        /// Creates a calendar style.
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

      /// Stores selection style data.
      public struct SelectionStyle: Sendable {
        /// The selected text color hex for this selection style.
        public var selectedTextColorHex: String
        /// The selected background color hex for this selection style.
        public var selectedBackgroundColorHex: String
        /// The selection date format for this selection style.
        public var selectionDateFormat: String
        /// The selection date separator for this selection style.
        public var selectionDateSeparator: String
        /// Whether the allows range selection option is enabled for this selection style.
        public var allowsRangeSelection: Bool
        /// Whether the reset selection on third tap option is enabled for this selection style.
        public var resetSelectionOnThirdTap: Bool

        /// Creates a selection style.
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

      /// Stores agenda style data.
      public struct AgendaStyle: Sendable {
        /// The layout for this agenda style.
        public var layout: CalendarMonthPopupLayout
        /// Whether the appointments scrollable option is enabled for this agenda style.
        public var appointmentsScrollable: Bool
        /// The appointments min height for this agenda style.
        public var appointmentsMinHeight: Double
        /// The appointments max height for this agenda style.
        public var appointmentsMaxHeight: Double
        /// The agenda title for this agenda style.
        public var agendaTitle: String
        /// The max visible appointments for this agenda style.
        public var maxVisibleAppointments: Int

        /// Creates an agenda style.
        public init(
          layout: CalendarMonthPopupLayout,
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

      /// Stores anchor style data.
      public struct AnchorStyle: Sendable {
        /// The date format for this anchor style.
        public var dateFormat: String
        /// The text color hex for this anchor style.
        public var textColorHex: String?
        /// Whether this anchor style shows date text.
        public var showDateText: Bool

        /// Creates an anchor style.
        public init(dateFormat: String, textColorHex: String?, showDateText: Bool) {
          self.dateFormat = dateFormat
          self.textColorHex = textColorHex
          self.showDateText = showDateText
        }
      }

      /// Stores today button style data.
      public struct TodayButtonStyle: Sendable {
        /// The title for this today button style.
        public var title: String
        /// The icon for this today button style.
        public var icon: String
        /// The padding x for this today button style.
        public var paddingX: Double
        /// The padding y for this today button style.
        public var paddingY: Double
        /// The margin x for this today button style.
        public var marginX: Double
        /// The margin y for this today button style.
        public var marginY: Double

        /// Creates a today button style.
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

      /// The style for this popup.
      public var style: Style
      /// The calendar for this popup.
      public var calendar: CalendarStyle
      /// The selection for this popup.
      public var selection: SelectionStyle
      /// The agenda for this popup.
      public var agenda: AgendaStyle
      /// The anchor for this popup.
      public var anchor: AnchorStyle
      /// The today button for this popup.
      public var todayButton: TodayButtonStyle

      /// Creates a popup.
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

    }
    /// The popup for this month.
    public var popup: Popup

    /// Creates a month.
    public init(popup: Popup) {
      self.popup = popup
    }
  }
}
