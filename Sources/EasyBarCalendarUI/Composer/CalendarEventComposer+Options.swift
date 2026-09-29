import EasyBarCalendarPresentation
import Foundation

extension CalendarEventComposer {
  /// Static timing metadata for one composer preset option.
  struct PresetMetadata {
    /// The seconds for this preset metadata.
    let seconds: TimeInterval?
  }

  /// Alert presets supported by the composer.
  public enum AlertOption: String, CaseIterable, Identifiable {
    case none
    case atTime = "at_time"
    case fiveMinutes = "5_minutes"
    case tenMinutes = "10_minutes"
    case fifteenMinutes = "15_minutes"
    case thirtyMinutes = "30_minutes"
    case oneHour = "1_hour"
    case oneDay = "1_day"
    case custom

    public var id: String { rawValue }

    var leadTimeSeconds: TimeInterval? {
      metadata.seconds
    }

    private var systemTitle: String {
      switch self {
      case .none:
        return CalendarComposerLocalizedText.none
      case .atTime:
        return CalendarComposerLocalizedText.atTimeOfEvent
      case .fiveMinutes, .tenMinutes, .fifteenMinutes, .thirtyMinutes, .oneHour, .oneDay:
        return CalendarComposerLocalizedText.alertBefore(seconds: metadata.seconds ?? 0)
      case .custom:
        return CalendarComposerLocalizedText.custom
      }
    }

    private var metadata: PresetMetadata {
      switch self {
      case .none:
        return PresetMetadata(seconds: nil)
      case .atTime:
        return PresetMetadata(seconds: 0)
      case .fiveMinutes:
        return PresetMetadata(seconds: 5 * 60)
      case .tenMinutes:
        return PresetMetadata(seconds: 10 * 60)
      case .fifteenMinutes:
        return PresetMetadata(seconds: 15 * 60)
      case .thirtyMinutes:
        return PresetMetadata(seconds: 30 * 60)
      case .oneHour:
        return PresetMetadata(seconds: 60 * 60)
      case .oneDay:
        return PresetMetadata(seconds: 24 * 60 * 60)
      case .custom:
        return PresetMetadata(seconds: nil)
      }
    }

    /// Returns the from.
    static func from(configValue: String) -> AlertOption {
      AlertOption(rawValue: configValue) ?? .oneHour
    }

    /// Returns the title.
    func title(config: CalendarComposerConfig) -> String {
      configuredPresetTitle(labels: config.alertLabels)
    }

    /// Returns the configured preset title.
    private func configuredPresetTitle(labels: [String: String]) -> String {
      labels[rawValue] ?? systemTitle
    }
  }

  /// Travel-time presets supported by the composer.
  public enum TravelTimeOption: String, CaseIterable, Identifiable {
    case none
    case fiveMinutes = "5_minutes"
    case tenMinutes = "10_minutes"
    case fifteenMinutes = "15_minutes"
    case twentyMinutes = "20_minutes"
    case thirtyMinutes = "30_minutes"
    case fortyFiveMinutes = "45_minutes"
    case oneHour = "1_hour"
    case ninetyMinutes = "90_minutes"
    case twoHours = "2_hours"
    case custom

    public var id: String { rawValue }

    var seconds: TimeInterval? {
      metadata.seconds
    }

    private var systemTitle: String {
      switch self {
      case .none:
        return CalendarComposerLocalizedText.none
      case .fiveMinutes, .tenMinutes, .fifteenMinutes, .twentyMinutes, .thirtyMinutes,
        .fortyFiveMinutes, .oneHour, .ninetyMinutes, .twoHours:
        return CalendarComposerLocalizedText.duration(seconds: metadata.seconds ?? 0)
      case .custom:
        return CalendarComposerLocalizedText.custom
      }
    }

    private var metadata: PresetMetadata {
      switch self {
      case .none:
        return PresetMetadata(seconds: nil)
      case .fiveMinutes:
        return PresetMetadata(seconds: 5 * 60)
      case .tenMinutes:
        return PresetMetadata(seconds: 10 * 60)
      case .fifteenMinutes:
        return PresetMetadata(seconds: 15 * 60)
      case .twentyMinutes:
        return PresetMetadata(seconds: 20 * 60)
      case .thirtyMinutes:
        return PresetMetadata(seconds: 30 * 60)
      case .fortyFiveMinutes:
        return PresetMetadata(seconds: 45 * 60)
      case .oneHour:
        return PresetMetadata(seconds: 60 * 60)
      case .ninetyMinutes:
        return PresetMetadata(seconds: 90 * 60)
      case .twoHours:
        return PresetMetadata(seconds: 2 * 60 * 60)
      case .custom:
        return PresetMetadata(seconds: nil)
      }
    }

    /// Returns the from.
    static func from(configValue: String) -> TravelTimeOption {
      TravelTimeOption(rawValue: configValue) ?? .none
    }

    /// Returns the title.
    func title(config: CalendarComposerConfig) -> String {
      configuredPresetTitle(labels: config.travelTimeLabels)
    }

    /// Returns the configured preset title.
    private func configuredPresetTitle(labels: [String: String]) -> String {
      labels[rawValue] ?? systemTitle
    }
  }
}
