import Foundation

/// Actions exposed by the native CPU widget context menu.
enum CPUContextMenuAction: Equatable {
  case setHistorySize(Int)
  case setSampleInterval(Int)
  case resetHistory
  case openActivityMonitor

  static let allowedHistorySizes = [10, 30, 60]
  static let allowedSampleIntervals = [1, 2, 5]
  static let customHistoryID = "cpu.history.custom"
  static let customIntervalID = "cpu.interval.custom"

  /// Stable context-menu action identifier.
  var id: String {
    switch self {
    case .setHistorySize(let size): return "cpu.history.\(size)"
    case .setSampleInterval(let seconds): return "cpu.interval.\(seconds)"
    case .resetHistory: return "cpu.reset_history"
    case .openActivityMonitor: return "cpu.open_activity_monitor"
    }
  }

  /// Decodes one stable context-menu action identifier.
  init?(id: String) {
    if let value = Self.allowedHistorySizes.first(where: { id == Self.setHistorySize($0).id }) {
      self = .setHistorySize(value)
      return
    }

    if let value = Self.allowedSampleIntervals.first(where: {
      id == Self.setSampleInterval($0).id
    }) {
      self = .setSampleInterval(value)
      return
    }

    switch id {
    case Self.resetHistory.id: self = .resetHistory
    case Self.openActivityMonitor.id: self = .openActivityMonitor
    default: return nil
    }
  }
}

/// Builds the native CPU context menu from the effective configuration.
enum CPUContextMenu {
  static func make(config: Config.CPUBuiltinConfig) -> [WidgetContextMenuItem] {
    var historyItems = CPUContextMenuAction.allowedHistorySizes.map { size in
      WidgetContextMenuItem(
        id: CPUContextMenuAction.setHistorySize(size).id,
        title: "\(size) Samples",
        checked: config.historySize == size
      )
    }

    if !CPUContextMenuAction.allowedHistorySizes.contains(config.historySize) {
      historyItems.insert(
        WidgetContextMenuItem(
          id: CPUContextMenuAction.customHistoryID,
          title: "Custom: \(config.historySize) Samples",
          enabled: false,
          checked: true
        ),
        at: 0
      )
    }

    var intervalItems = CPUContextMenuAction.allowedSampleIntervals.map { seconds in
      WidgetContextMenuItem(
        id: CPUContextMenuAction.setSampleInterval(seconds).id,
        title: seconds == 1 ? "1 Second" : "\(seconds) Seconds",
        checked: config.sampleIntervalSeconds == Double(seconds)
      )
    }

    if !CPUContextMenuAction.allowedSampleIntervals.contains(where: {
      config.sampleIntervalSeconds == Double($0)
    }) {
      intervalItems.insert(
        WidgetContextMenuItem(
          id: CPUContextMenuAction.customIntervalID,
          title: "Custom: \(formattedSeconds(config.sampleIntervalSeconds)) Seconds",
          enabled: false,
          checked: true
        ),
        at: 0
      )
    }

    return [
      WidgetContextMenuItem(
        id: CPUContextMenuAction.openActivityMonitor.id,
        title: "Open Activity Monitor"
      ),
      WidgetContextMenuItem(separator: true),
      WidgetContextMenuItem(title: "History", submenu: historyItems),
      WidgetContextMenuItem(title: "Refresh Interval", submenu: intervalItems),
      WidgetContextMenuItem(separator: true),
      WidgetContextMenuItem(
        id: CPUContextMenuAction.resetHistory.id,
        title: "Reset History"
      ),
    ]
  }

  private static func formattedSeconds(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0...3)))
  }
}
