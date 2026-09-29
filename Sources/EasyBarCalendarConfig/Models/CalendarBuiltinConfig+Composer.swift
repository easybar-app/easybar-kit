import Foundation

extension CalendarBuiltinConfig {
  /// Stores composer data.
  public struct Composer: Sendable {
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
      /// The header text color hex for this style.
      public var headerTextColorHex: String

      /// Creates a style.
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

    /// Stores content data.
    public struct Content: Sendable {
      /// The create title for this content.
      public var createTitle: String
      /// The edit title for this content.
      public var editTitle: String
      /// The title label for this content.
      public var titleLabel: String
      /// The location label for this content.
      public var locationLabel: String
      /// The calendar label for this content.
      public var calendarLabel: String
      /// The title placeholder for this content.
      public var titlePlaceholder: String
      /// The location placeholder for this content.
      public var locationPlaceholder: String
      /// The default calendar name for this content.
      public var defaultCalendarName: String?
      /// The default alert for this content.
      public var defaultAlert: String
      /// The default travel time for this content.
      public var defaultTravelTime: String
      /// The alert labels for this content.
      public var alertLabels: [String: String]
      /// The travel time labels for this content.
      public var travelTimeLabels: [String: String]
      /// The start label for this content.
      public var startLabel: String
      /// The end label for this content.
      public var endLabel: String
      /// The all day label for this content.
      public var allDayLabel: String
      /// The travel time label for this content.
      public var travelTimeLabel: String
      /// The alert label for this content.
      public var alertLabel: String
      /// The add alert label for this content.
      public var addAlertLabel: String
      /// The open calendar label for this content.
      public var openCalendarLabel: String
      /// Whether this content can cel label.
      public var cancelLabel: String
      /// The save label for this content.
      public var saveLabel: String
      /// The update label for this content.
      public var updateLabel: String
      /// The remove label for this content.
      public var removeLabel: String
      /// The delete confirmation title for this content.
      public var deleteConfirmationTitle: String
      /// The delete confirmation message for this content.
      public var deleteConfirmationMessage: String

      /// Creates a content.
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

    /// The style for this composer.
    public var style: Style
    /// The content for this composer.
    public var content: Content

    /// Creates a composer.
    public init(style: Style, content: Content) {
      self.style = style
      self.content = content
    }

  }
}
