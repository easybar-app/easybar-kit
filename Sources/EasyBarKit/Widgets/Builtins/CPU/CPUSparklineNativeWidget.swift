import AppKit
import Darwin.Mach
import EasyBarShared
import Foundation
import SwiftTOMLEdit

/// Native CPU widget that samples system usage and renders a sparkline.
@MainActor
final class CPUSparklineNativeWidget: NativeWidget {

  let rootID = "builtin_cpu"
  let widgetStore: WidgetStore

  var appEventSubscriptions: Set<String> {
    [
      AppEvent.secondTick.rawValue,
      AppEvent.systemWoke.rawValue,
    ]
  }

  private var config: Config.CPUBuiltinConfig
  private let configSnapshotStore: ConfigSnapshotStore
  private let configPersistence: ConfigPersistence
  private let eventObserver: EasyBarEventObserver
  private let logger: ProcessLogger
  private var samples: [Double] = []
  private var previousCPUInfo: host_cpu_load_info_data_t?
  private var lastSampleDate: Date?
  private var isRunning = false

  /// Creates the native CPU widget from an immutable config section.
  init(
    config: Config.CPUBuiltinConfig,
    widgetStore: WidgetStore,
    configSnapshotStore: ConfigSnapshotStore,
    configPersistence: ConfigPersistence,
    eventHub: EventHub,
    logger: ProcessLogger
  ) {
    self.config = config
    self.widgetStore = widgetStore
    self.configSnapshotStore = configSnapshotStore
    self.configPersistence = configPersistence
    self.eventObserver = EasyBarEventObserver(eventHub: eventHub)
    self.logger = logger
  }

  /// Starts CPU sampling and publishes the initial widget state.
  func start() {
    guard !isRunning else { return }

    isRunning = true
    samples = Array(repeating: 0, count: historySize)
    previousCPUInfo = readCPUInfo()
    lastSampleDate = nil

    eventObserver.start(
      eventNames: appEventSubscriptions.union([WidgetEvent.contextMenuClicked.rawValue]),
      widgetTargetIDs: [rootID]
    ) { [weak self] payload in
      guard let self else { return }

      if payload.widgetEvent == .contextMenuClicked,
        payload.widgetID == self.rootID,
        let actionID = payload.actionID
      {
        self.handleContextMenuAction(actionID)
        return
      }

      guard let event = payload.appEvent else { return }

      switch event {
      case .secondTick:
        self.sampleAndPublishIfNeeded()

      case .systemWoke:
        // Reset the baseline because CPU tick counters can jump after wake.
        self.previousCPUInfo = self.readCPUInfo()
        self.lastSampleDate = nil
        self.publish()

      case .intervalTick:
        break

      default:
        break
      }
    }

    publish()
  }

  /// Stops CPU sampling and removes the rendered widget nodes.
  func stop() {
    guard isRunning else { return }

    isRunning = false
    eventObserver.stop()
    samples.removeAll()
    previousCPUInfo = nil
    lastSampleDate = nil

    clearNodes()
  }

  /// Reads one CPU sample when the configured interval has elapsed.
  private func sampleAndPublishIfNeeded() {
    let now = Date()

    guard shouldSample(at: now) else {
      return
    }

    sampleAndPublish(at: now)
  }

  /// Returns whether enough time has passed for the next CPU sample.
  private func shouldSample(at date: Date) -> Bool {
    guard let lastSampleDate else {
      return true
    }

    return date.timeIntervalSince(lastSampleDate) >= sampleIntervalSeconds
  }

  /// Reads one CPU sample and publishes the current widget state.
  private func sampleAndPublish(at date: Date) {
    lastSampleDate = date

    guard let usage = readCPUUsagePercent() else {
      publish()
      return
    }

    pushSample(usage)
    publish()
  }

  /// Publishes the current CPU sparkline to the widget store.
  private func publish() {
    var node = BuiltinNativeNodeFactory.makeSparklineNode(
      rootID: rootID,
      placement: config.placement,
      style: config.style,
      text: config.label,
      values: samples,
      lineWidth: config.lineWidth,
      color: config.colorHex ?? config.style.textColorHex
    )
    node.contextMenu = CPUContextMenu.make(config: config)
    applyNodes([node])
  }

  /// Appends one clamped CPU sample and keeps the configured history size.
  private func pushSample(_ value: Double) {
    samples.append(min(max(value, 0), 100))
    resizeHistory()
  }

  /// Resizes the current sample buffer while preserving the newest values.
  private func resizeHistory() {
    if samples.count > historySize {
      samples.removeFirst(samples.count - historySize)
    }

    if samples.count < historySize {
      samples.insert(contentsOf: repeatElement(0, count: historySize - samples.count), at: 0)
    }
  }

  /// Returns the configured sample history size.
  private var historySize: Int {
    return max(2, config.historySize)
  }

  /// Returns the configured CPU sample interval in seconds.
  private var sampleIntervalSeconds: TimeInterval {
    return max(1, config.sampleIntervalSeconds)
  }

  // MARK: - Context Menu

  /// Handles one CPU-specific native context-menu action.
  private func handleContextMenuAction(_ actionID: String) {
    guard let action = CPUContextMenuAction(id: actionID) else { return }

    switch action {
    case .setHistorySize(let size):
      var updated = config
      updated.historySize = size
      guard
        persist(
          updated,
          edit: TOMLEdit(
            path: ["builtins", "cpu", "content", "history_size"],
            value: .integer(size)
          )
        )
      else { return }
      resizeHistory()
      publish()

    case .setSampleInterval(let seconds):
      var updated = config
      updated.sampleIntervalSeconds = Double(seconds)
      guard
        persist(
          updated,
          edit: TOMLEdit(
            path: ["builtins", "cpu", "content", "sample_interval_seconds"],
            value: .integer(seconds)
          )
        )
      else { return }
      lastSampleDate = nil
      publish()

    case .resetHistory:
      samples = Array(repeating: 0, count: historySize)
      previousCPUInfo = readCPUInfo()
      lastSampleDate = nil
      publish()

    case .openActivityMonitor:
      guard
        let url = NSWorkspace.shared.urlForApplication(
          withBundleIdentifier: "com.apple.ActivityMonitor"
        )
      else {
        logger.warn("Activity Monitor application was not found")
        return
      }
      guard NSWorkspace.shared.open(url) else {
        logger.warn("failed to open Activity Monitor")
        return
      }
      logger.debug("opened Activity Monitor")
    }
  }

  @discardableResult
  private func persist(_ updated: Config.CPUBuiltinConfig, edit: TOMLEdit) -> Bool {
    NativeWidgetConfigUpdate.persist(edits: [edit], using: configPersistence) {
      config = updated
      configSnapshotStore.applyCPUOverride(updated)
    }
  }

  /// Reads cumulative CPU tick counters from Mach.
  private func readCPUInfo() -> host_cpu_load_info_data_t? {
    let host = mach_host_self()
    defer {
      mach_port_deallocate(mach_task_self_, host)
    }

    var info = host_cpu_load_info_data_t()
    var count = mach_msg_type_number_t(
      MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride
    )

    let status = withUnsafeMutablePointer(to: &info) { pointer in
      pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
        host_statistics(
          host,
          HOST_CPU_LOAD_INFO,
          rebound,
          &count
        )
      }
    }

    return status == KERN_SUCCESS ? info : nil
  }

  /// Calculates whole-system CPU usage from the delta between two Mach samples.
  private func readCPUUsagePercent() -> Double? {
    guard let current = readCPUInfo() else { return nil }

    defer {
      previousCPUInfo = current
    }

    guard let previous = previousCPUInfo else {
      return nil
    }

    guard
      let user = tickDelta(current.cpu_ticks.0, previous.cpu_ticks.0),
      let system = tickDelta(current.cpu_ticks.1, previous.cpu_ticks.1),
      let idle = tickDelta(current.cpu_ticks.2, previous.cpu_ticks.2),
      let nice = tickDelta(current.cpu_ticks.3, previous.cpu_ticks.3)
    else {
      return nil
    }

    let active = user + system + nice
    let total = active + idle

    guard total > 0 else { return 0 }

    let percent = (Double(active) / Double(total)) * 100.0
    return min(max(percent, 0), 100)
  }

  /// Returns a safe positive tick delta, or nil if counters moved backwards.
  private func tickDelta(_ current: natural_t, _ previous: natural_t) -> UInt64? {
    let current = UInt64(current)
    let previous = UInt64(previous)

    guard current >= previous else {
      return nil
    }

    return current - previous
  }
}
