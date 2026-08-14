import EasyBarShared
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
        public var layout: CalendarMonthPopupLayout
        public var appointmentsScrollable: Bool
        public var appointmentsMinHeight: Double
        public var appointmentsMaxHeight: Double
        public var agendaTitle: String
        public var maxVisibleAppointments: Int

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

    }
    public var popup: Popup

    public init(popup: Popup) {
      self.popup = popup
    }
  }
}
