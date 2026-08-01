import AppKit
import EasyBarShared
import Foundation

/// Observes AppKit and workspace system events.
final class SystemEvents: @unchecked Sendable {
  /// Shared system event source.
  /// Logger used for system event diagnostics.
  private let logger: ProcessLogger
  private let eventHub: EventHub

  /// Active notification observers keyed by kind.
  private var observers: [ObserverKind: NSObjectProtocol] = [:]
  /// Pending coalesced wake emission.
  private var pendingWakeTask: Task<Void, Never>?
  /// Identifier for the pending coalesced wake emission.
  private var pendingWakeEmissionID: UInt64?
  /// Next coalesced wake emission identifier.
  private var nextWakeEmissionID: UInt64 = 1

  /// Notification observer category.
  private enum ObserverKind: Hashable {
    /// System wake observer.
    case systemWake
    /// Session became active observer.
    case sessionActive
    /// Session became inactive observer.
    case sessionInactive
    /// System sleep observer.
    case sleep
    /// Active space observer.
    case spaceChange
    /// Frontmost app observer.
    case appSwitch
    /// Display configuration observer.
    case displayChange
  }

  /// Creates one system event source.
  init(logger: ProcessLogger, eventHub: EventHub) {
    self.logger = logger
    self.eventHub = eventHub
  }

  /// Starts observation for system wake notifications.
  func subscribeSystemWake() {
    guard observers[.systemWake] == nil else { return }

    let observer = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didWakeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.scheduleWakeEmission()
    }

    observers[.systemWake] = observer
    logger.debug("subscribed system_woke")
  }

  /// Stops observation for system wake notifications.
  func unsubscribeSystemWake() {
    removeObserver(.systemWake)
  }

  /// Starts observation for session active notifications.
  func subscribeSessionActive() {
    guard observers[.sessionActive] == nil else { return }

    let observer = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.sessionDidBecomeActiveNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      guard let self else { return }

      self.logger.debug("received workspace sessionDidBecomeActive notification")

      Task {
        await self.eventHub.emit(.sessionActive)
      }
    }

    observers[.sessionActive] = observer
    logger.debug("subscribed session_active")
  }

  /// Stops observation for session active notifications.
  func unsubscribeSessionActive() {
    removeObserver(.sessionActive)
  }

  /// Starts observation for session inactive notifications.
  func subscribeSessionInactive() {
    guard observers[.sessionInactive] == nil else { return }

    let observer = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.sessionDidResignActiveNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      guard let self else { return }

      self.logger.debug("received workspace sessionDidResignActive notification")

      Task {
        await self.eventHub.emit(.sessionInactive)
      }
    }

    observers[.sessionInactive] = observer
    logger.debug("subscribed session_inactive")
  }

  /// Stops observation for session inactive notifications.
  func unsubscribeSessionInactive() {
    removeObserver(.sessionInactive)
  }

  /// Starts observation for system sleep notifications.
  func subscribeSleep() {
    guard observers[.sleep] == nil else { return }

    let observer = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.willSleepNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      guard let self else { return }

      self.logger.debug("received workspace willSleep notification")

      Task {
        await self.eventHub.emit(.sleep)
      }
    }

    observers[.sleep] = observer
    logger.debug("subscribed sleep")
  }

  /// Stops observation for system sleep notifications.
  func unsubscribeSleep() {
    removeObserver(.sleep)
  }

  /// Starts observation for active space changes.
  func subscribeSpaceChange() {
    guard observers[.spaceChange] == nil else { return }

    let observer = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.activeSpaceDidChangeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      guard let self else { return }

      self.logger.debug("received workspace activeSpaceDidChange notification")

      Task {
        await self.eventHub.emit(.spaceChange)
      }
    }

    observers[.spaceChange] = observer
    logger.debug("subscribed space_change")
  }

  /// Stops observation for active space changes.
  func unsubscribeSpaceChange() {
    removeObserver(.spaceChange)
  }

  /// Starts observation for frontmost app changes.
  func subscribeAppSwitch() {
    guard observers[.appSwitch] == nil else { return }

    let observer = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      guard let self else { return }

      guard
        let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
          as? NSRunningApplication
      else {
        self.logger.debug("received didActivateApplication notification without app payload")
        return
      }

      let appName = app.localizedName ?? ""
      self.logger.debug(
        "received didActivateApplication notification",
        .field("app", appName)
      )

      Task {
        await self.eventHub.emit(.app(.appSwitch, appName: appName))
      }
    }

    observers[.appSwitch] = observer
    logger.debug("subscribed app_switch")
  }

  /// Stops observation for frontmost app changes.
  func unsubscribeAppSwitch() {
    removeObserver(.appSwitch)
  }

  /// Starts observation for display configuration changes.
  func subscribeDisplayChange() {
    guard observers[.displayChange] == nil else { return }

    let observer = NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      guard let self else { return }

      self.logger.debug("received didChangeScreenParameters notification")

      Task {
        await self.eventHub.emit(.displayChange)
      }
    }

    observers[.displayChange] = observer
    logger.debug("subscribed display_change")
  }

  /// Stops observation for display configuration changes.
  func unsubscribeDisplayChange() {
    removeObserver(.displayChange)
  }

  /// Removes every registered system observer.
  func stopAll() {
    pendingWakeTask?.cancel()
    pendingWakeTask = nil
    pendingWakeEmissionID = nil
    unsubscribeSystemWake()
    unsubscribeSessionActive()
    unsubscribeSessionInactive()
    unsubscribeSleep()
    unsubscribeSpaceChange()
    unsubscribeAppSwitch()
    unsubscribeDisplayChange()
    logger.debug("stopped all system event observers")
  }

  /// Coalesces near-simultaneous wake-related notifications into one app event.
  private func scheduleWakeEmission() {
    logger.debug("received workspace didWake notification")

    pendingWakeTask?.cancel()

    let wakeEmissionID = nextWakeEmissionID
    nextWakeEmissionID &+= 1
    pendingWakeEmissionID = wakeEmissionID

    pendingWakeTask = Task { [weak self] in
      do {
        try await Task.sleep(for: .milliseconds(150))
      } catch {
        return
      }

      guard let self else { return }
      let shouldEmit = await MainActor.run {
        self.clearPendingWakeEmission(id: wakeEmissionID)
      }
      guard shouldEmit else { return }

      await MainActor.run {
        self.logger.debug("emitting coalesced system_woke")
      }

      await eventHub.emit(.systemWoke)
    }
  }

  /// Clears the pending wake emission if it still matches the fired task.
  private func clearPendingWakeEmission(id: UInt64) -> Bool {
    guard pendingWakeEmissionID == id else { return false }
    pendingWakeTask = nil
    pendingWakeEmissionID = nil
    return true
  }

  /// Removes one registered observer when present.
  private func removeObserver(_ kind: ObserverKind) {
    guard let observer = observers.removeValue(forKey: kind) else { return }

    NSWorkspace.shared.notificationCenter.removeObserver(observer)
    NotificationCenter.default.removeObserver(observer)
  }
}
