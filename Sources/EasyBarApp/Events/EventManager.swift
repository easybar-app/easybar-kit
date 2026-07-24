import EasyBarShared
import Foundation

/// Main-actor owner of native event source subscriptions.
@MainActor
final class EventManager {
  /// Shared event manager instance.
  /// Prefix used for Lua interval subscriptions.
  private static let intervalTickPrefix = "interval_tick:"
  private static let maximumIntervalSeconds: TimeInterval = 365 * 24 * 60 * 60
  /// Native event source managed by subscription demand.
  private enum ManagedSource: Hashable {
    /// System wake notifications.
    case systemWake
    /// Session active notifications.
    case sessionActive
    /// Session inactive notifications.
    case sessionInactive
    /// System sleep notifications.
    case sleep
    /// Active space change notifications.
    case spaceChange
    /// Frontmost app change notifications.
    case appSwitch
    /// Display configuration notifications.
    case displayChange
    /// Camera and microphone inventory and activity notifications.
    case captureDevices
    /// Power source and charging notifications.
    case powerSource
    /// Volume and mute notifications.
    case volume
    /// Minute timer source.
    case minuteTick
    /// Second timer source.
    case secondTick
  }

  /// External description of required native event sources.
  struct SubscriptionPlan: Equatable {
    /// Required source names.
    let sources: Set<String>
    /// Requested widget-scoped interval schedules.
    let intervalSchedules: Set<WidgetIntervalSchedule>
  }

  /// Logger used for event manager diagnostics.
  private let logger: ProcessLogger
  /// System-level notification source.
  private let systemEvents: SystemEvents
  /// Power notification source.
  private let powerEvents: PowerEvents
  /// Timer event source.
  private let timerEvents: TimerEvents
  /// Volume notification source.
  private let volumeEvents: VolumeEvents
  /// Camera and microphone notification source.
  private let captureDeviceEvents: CaptureDeviceEvents

  /// Event names requested by Lua widgets.
  private var luaRequestedEvents = Set<String>()
  /// Event names requested by native widgets.
  private var nativeRequestedEvents = Set<String>()
  /// Last applied merged subscription set.
  private var activeRequestedEvents = Set<String>()
  /// Currently active native event sources.
  private var activeSources = Set<ManagedSource>()
  /// Currently active widget-scoped interval schedules.
  private var activeIntervalSchedules = Set<WidgetIntervalSchedule>()

  /// Creates one event manager.
  init(
    logger: ProcessLogger,
    systemEvents: SystemEvents,
    powerEvents: PowerEvents,
    timerEvents: TimerEvents,
    volumeEvents: VolumeEvents,
    captureDeviceEvents: CaptureDeviceEvents
  ) {
    self.logger = logger
    self.systemEvents = systemEvents
    self.powerEvents = powerEvents
    self.timerEvents = timerEvents
    self.volumeEvents = volumeEvents
    self.captureDeviceEvents = captureDeviceEvents
  }

  /// Replaces the current Lua runtime event subscriptions.
  func setLuaSubscriptions(_ subscriptions: Set<String>) {
    let addedEvents = subscriptions.subtracting(luaRequestedEvents)
    luaRequestedEvents = subscriptions
    refresh()
    captureDeviceEvents.publishCurrentSnapshot(for: addedEvents)
  }

  /// Replaces the current native widget event subscriptions.
  func setNativeSubscriptions(_ subscriptions: Set<String>) {
    let addedEvents = subscriptions.subtracting(nativeRequestedEvents)
    nativeRequestedEvents = subscriptions
    refresh()
    captureDeviceEvents.publishCurrentSnapshot(for: addedEvents)
  }

  /// Stops only Lua-owned event subscriptions while preserving native ones.
  func stopLuaSubscriptions() {
    guard !luaRequestedEvents.isEmpty else { return }

    luaRequestedEvents.removeAll()
    refresh()
  }

  /// Stops all active native event sources and clears every subscription source.
  func stopAll() {
    logger.debug("event manager stopAll begin")

    luaRequestedEvents.removeAll()
    nativeRequestedEvents.removeAll()
    stopActiveSources()
    activeRequestedEvents.removeAll()
    activeSources.removeAll()
    activeIntervalSchedules.removeAll()

    logger.debug("event manager stopAll end")
  }

  /// Rebuilds active event listeners from the merged Lua and native subscriptions.
  private func refresh() {
    let mergedRequestedEvents = luaRequestedEvents.union(nativeRequestedEvents)

    if mergedRequestedEvents == activeRequestedEvents {
      logger.debug("event manager refresh skipped, requested events unchanged")
      return
    }

    let addedEvents = mergedRequestedEvents.subtracting(activeRequestedEvents)
    let removedEvents = activeRequestedEvents.subtracting(mergedRequestedEvents)
    let desiredSources = Self.requiredSources(for: mergedRequestedEvents)
    let sourcesToAdd = desiredSources.subtracting(activeSources)
    let sourcesToRemove = activeSources.subtracting(desiredSources)
    let desiredIntervalSchedules = Self.intervalTickSchedules(in: mergedRequestedEvents)
    let intervalChanged = desiredIntervalSchedules != activeIntervalSchedules

    logger.debug(
      "event manager refresh begin",
      .field("merged_requested_events", "\(mergedRequestedEvents)"),
      .field("active_requested_events", "\(activeRequestedEvents)"),
      .field("added_events", "\(addedEvents)"),
      .field("removed_events", "\(removedEvents)"),
      .field("source_add", "\(sourcesToAdd)"),
      .field("source_remove", "\(sourcesToRemove)"),
      .field("interval_schedules", "\(desiredIntervalSchedules)"),
      .field("previous_interval_schedules", "\(activeIntervalSchedules)"),
      .field("lua_requested_events", "\(luaRequestedEvents)"),
      .field("native_requested_events", "\(nativeRequestedEvents)"),
    )

    unsubscribeSources(sourcesToRemove)

    activeRequestedEvents = mergedRequestedEvents
    subscribeSources(sourcesToAdd)

    if intervalChanged {
      timerEvents.replaceIntervalTimers(schedules: desiredIntervalSchedules)
    }

    activeSources = desiredSources
    activeIntervalSchedules = desiredIntervalSchedules

    logger.debug(
      "event manager refresh end",
      .field("active_requested_events", activeRequestedEvents),
    )
  }

  /// Starts the newly required event sources.
  private func subscribeSources(_ sources: Set<ManagedSource>) {
    for source in sources {
      switch source {
      case .systemWake:
        systemEvents.subscribeSystemWake()
      case .sessionActive:
        systemEvents.subscribeSessionActive()
      case .sessionInactive:
        systemEvents.subscribeSessionInactive()
      case .sleep:
        systemEvents.subscribeSleep()
      case .spaceChange:
        systemEvents.subscribeSpaceChange()
      case .appSwitch:
        systemEvents.subscribeAppSwitch()
      case .displayChange:
        systemEvents.subscribeDisplayChange()
      case .captureDevices:
        captureDeviceEvents.start()
      case .powerSource:
        powerEvents.subscribePowerSource()
      case .volume:
        volumeEvents.subscribeVolume()
      case .minuteTick:
        timerEvents.startMinuteTimer()
      case .secondTick:
        timerEvents.startSecondTimer()
      }
    }
  }

  /// Stops the event sources that are no longer required.
  private func unsubscribeSources(_ sources: Set<ManagedSource>) {
    for source in sources {
      switch source {
      case .systemWake:
        systemEvents.unsubscribeSystemWake()
      case .sessionActive:
        systemEvents.unsubscribeSessionActive()
      case .sessionInactive:
        systemEvents.unsubscribeSessionInactive()
      case .sleep:
        systemEvents.unsubscribeSleep()
      case .spaceChange:
        systemEvents.unsubscribeSpaceChange()
      case .appSwitch:
        systemEvents.unsubscribeAppSwitch()
      case .displayChange:
        systemEvents.unsubscribeDisplayChange()
      case .captureDevices:
        captureDeviceEvents.stop()
      case .powerSource:
        powerEvents.unsubscribePowerSource()
      case .volume:
        volumeEvents.unsubscribeVolume()
      case .minuteTick:
        timerEvents.stopMinuteTimer()
      case .secondTick:
        timerEvents.stopSecondTimer()
      }
    }
  }

  /// Stops every currently active native event source.
  private func stopActiveSources() {
    timerEvents.stopAll()
    systemEvents.stopAll()
    powerEvents.stopAll()
    volumeEvents.stopAll()
    captureDeviceEvents.stop()
  }

  /// Returns the concrete native sources required by the merged subscription set.
  private static func requiredSources(for subscriptions: Set<String>) -> Set<ManagedSource> {
    var sources = Set<ManagedSource>()

    if subscriptions.contains(AppEvent.systemWoke.rawValue) {
      sources.insert(.systemWake)
    }

    if subscriptions.contains(AppEvent.sessionActive.rawValue) {
      sources.insert(.sessionActive)
    }

    if subscriptions.contains(AppEvent.sessionInactive.rawValue) {
      sources.insert(.sessionInactive)
    }

    if subscriptions.contains(AppEvent.sleep.rawValue) {
      sources.insert(.sleep)
    }

    if subscriptions.contains(AppEvent.spaceChange.rawValue) {
      sources.insert(.spaceChange)
    }

    if subscriptions.contains(AppEvent.appSwitch.rawValue) {
      sources.insert(.appSwitch)
    }

    if subscriptions.contains(AppEvent.displayChange.rawValue) {
      sources.insert(.displayChange)
    }

    if !subscriptions.isDisjoint(with: CaptureDeviceEvents.eventNames) {
      sources.insert(.captureDevices)
    }

    if subscriptions.contains(AppEvent.powerSourceChange.rawValue)
      || subscriptions.contains(AppEvent.chargingStateChange.rawValue)
    {
      sources.insert(.powerSource)
    }

    if subscriptions.contains(AppEvent.volumeChange.rawValue)
      || subscriptions.contains(AppEvent.muteChange.rawValue)
    {
      sources.insert(.volume)
    }

    if subscriptions.contains(AppEvent.minuteTick.rawValue) {
      sources.insert(.minuteTick)
    }

    if subscriptions.contains(AppEvent.secondTick.rawValue) {
      sources.insert(.secondTick)
    }

    return sources
  }

  /// Returns the external subscription plan used to activate native sources.
  static func subscriptionPlan(for subscriptions: Set<String>) -> SubscriptionPlan {
    SubscriptionPlan(
      sources: requiredSources(for: subscriptions).map { String(describing: $0) }.reduce(
        into: Set<String>()
      ) { result, source in
        result.insert(source)
      },
      intervalSchedules: intervalTickSchedules(in: subscriptions)
    )
  }

  /// Returns the widget-scoped Lua interval schedules requested by the runtime.
  private static func intervalTickSchedules(in subscriptions: Set<String>) -> Set<
    WidgetIntervalSchedule
  > {
    Set(
      subscriptions.compactMap { name in
        guard name.hasPrefix(intervalTickPrefix) else { return nil }

        let rawValue = String(name.dropFirst(intervalTickPrefix.count))
        let parts = rawValue.split(separator: ":", omittingEmptySubsequences: false)

        guard parts.count == 2 else { return nil }

        let widgetID = String(parts[0])
        guard
          !widgetID.isEmpty,
          let interval = TimeInterval(parts[1]),
          interval.isFinite,
          interval > 0,
          interval <= maximumIntervalSeconds
        else { return nil }

        return WidgetIntervalSchedule(widgetID: widgetID, interval: interval)
      })
  }
}
