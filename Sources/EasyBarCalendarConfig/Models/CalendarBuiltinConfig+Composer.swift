import Foundation

extension CalendarBuiltinConfig {
  public struct Composer: Sendable {
    public struct Style: Sendable {
      public var backgroundColorHex: String
      public var borderColorHex: String
      public var borderWidth: Double
      public var cornerRadius: Double
      public var paddingX: Double
      public var paddingY: Double
      public var headerTextColorHex: String

      public init(
        backgroundColorHex: String,
        borderColorHex: String,
        borderWidth: Double,
        cornerRadius: Double,
        paddingX: Double,
        paddingY: Double,
        headerTextColorHex: String
      ) {
        self.backgroundColorHex = backgroundColorHex
        self.borderColorHex = borderColorHex
        self.borderWidth = borderWidth
        self.cornerRadius = cornerRadius
        self.paddingX = paddingX
        self.paddingY = paddingY
        self.headerTextColorHex = headerTextColorHex
      }
    }

    public struct Content: Sendable {
      public var createTitle: String
      public var editTitle: String
      public var titleLabel: String
      public var locationLabel: String
      public var calendarLabel: String
      public var titlePlaceholder: String
      public var locationPlaceholder: String
      public var defaultCalendarName: String?
      public var defaultAlert: String
      public var defaultTravelTime: String
      public var alertLabels: [String: String]
      public var travelTimeLabels: [String: String]
      public var startLabel: String
      public var endLabel: String
      public var allDayLabel: String
      public var travelTimeLabel: String
      public var alertLabel: String
      public var addAlertLabel: String
      public var openCalendarLabel: String
      public var cancelLabel: String
      public var saveLabel: String
      public var updateLabel: String
      public var removeLabel: String
      public var deleteConfirmationTitle: String
      public var deleteConfirmationMessage: String

      public init(
        createTitle: String,
        editTitle: String,
        titleLabel: String,
        locationLabel: String,
        calendarLabel: String,
        titlePlaceholder: String,
        locationPlaceholder: String,
        defaultCalendarName: String?,
        defaultAlert: String,
        defaultTravelTime: String,
        alertLabels: [String: String],
        travelTimeLabels: [String: String],
        startLabel: String,
        endLabel: String,
        allDayLabel: String,
        travelTimeLabel: String,
        alertLabel: String,
        addAlertLabel: String,
        openCalendarLabel: String,
        cancelLabel: String,
        saveLabel: String,
        updateLabel: String,
        removeLabel: String,
        deleteConfirmationTitle: String,
        deleteConfirmationMessage: String
      ) {
        self.createTitle = createTitle
        self.editTitle = editTitle
        self.titleLabel = titleLabel
        self.locationLabel = locationLabel
        self.calendarLabel = calendarLabel
        self.titlePlaceholder = titlePlaceholder
        self.locationPlaceholder = locationPlaceholder
        self.defaultCalendarName = defaultCalendarName
        self.defaultAlert = defaultAlert
        self.defaultTravelTime = defaultTravelTime
        self.alertLabels = alertLabels
        self.travelTimeLabels = travelTimeLabels
        self.startLabel = startLabel
        self.endLabel = endLabel
        self.allDayLabel = allDayLabel
        self.travelTimeLabel = travelTimeLabel
        self.alertLabel = alertLabel
        self.addAlertLabel = addAlertLabel
        self.openCalendarLabel = openCalendarLabel
        self.cancelLabel = cancelLabel
        self.saveLabel = saveLabel
        self.updateLabel = updateLabel
        self.removeLabel = removeLabel
        self.deleteConfirmationTitle = deleteConfirmationTitle
        self.deleteConfirmationMessage = deleteConfirmationMessage
      }
    }

    public var style: Style
    public var content: Content

    public init(style: Style, content: Content) {
      self.style = style
      self.content = content
    }

  }
}
