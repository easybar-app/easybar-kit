import CoreLocation
import EasyBarShared
import Foundation

/// One atomically sampled location-authorization state.
struct NetworkAuthorizationSnapshot: Equatable, Sendable {
  /// Whether this network authorization snapshot is authorized.
  let isAuthorized: Bool
  /// The permission state for this network authorization snapshot.
  let permissionState: String

  /// Creates a network authorization snapshot.
  init(status: CLAuthorizationStatus) {
    switch status {
    case .authorized, .authorizedAlways, .authorizedWhenInUse:
      isAuthorized = true
    default:
      isAuthorized = false
    }

    switch status {
    case .notDetermined: permissionState = "not_determined"
    case .restricted: permissionState = "restricted"
    case .denied: permissionState = "denied"
    case .authorized: permissionState = "authorized"
    case .authorizedAlways: permissionState = "authorized_always"
    case .authorizedWhenInUse: permissionState = "authorized_when_in_use"
    @unknown default: permissionState = "unknown"
    }
  }
}

/// Coordinates CoreLocation authorization for network data.
final class NetworkLocationAuthorizationController: NSObject, CLLocationManagerDelegate,
  @unchecked Sendable
{
  private let locationManager = CLLocationManager()
  private let authorizationStatus = LockedState(CLAuthorizationStatus.notDetermined)
  private let componentName: String
  private let logger: ProcessLogger
  private let lifecycle: AuthorizationLifecycle
  private weak var promptPresenter: NetworkAuthorizationPromptPresenter?

  /// Session that currently owns the temporary authorization prompt UI.
  private let promptOwner = LockedState<ObjectIdentifier?>(nil)

  /// Creates one location authorization controller that logs through the provided logger.
  init(
    componentName: String,
    logger: ProcessLogger,
    promptPresenter: NetworkAuthorizationPromptPresenter?
  ) {
    self.componentName = componentName
    self.logger = logger
    self.promptPresenter = promptPresenter
    lifecycle = AuthorizationLifecycle(logger: logger)

    super.init()
  }

  /// Starts tracking and requesting location authorization when needed.
  func start(onChange: @escaping () -> Void) {
    if let previousSession = lifecycle.currentSession() {
      restoreAccessoryModeIfNeeded(for: previousSession)
    }

    let session = lifecycle.start(onChange: onChange)
    locationManager.delegate = self

    let status = locationManager.authorizationStatus
    setAuthorizationStatus(status)

    logger.info(
      "\(componentName) authorization status before",
      .field("start", permissionState())
    )

    requestAccessIfNeeded(for: session)
  }

  /// Stops authorization callbacks and invalidates pending work.
  func stop() {
    if let session = lifecycle.currentSession() {
      restoreAccessoryModeIfNeeded(for: session)
    }

    locationManager.delegate = nil
    lifecycle.stop()
  }

  /// Samples authorization once so permission fields cannot disagree.
  func snapshot() -> NetworkAuthorizationSnapshot {
    NetworkAuthorizationSnapshot(status: currentAuthorizationStatus())
  }

  /// Returns whether location access is currently authorized.
  func isAuthorized() -> Bool {
    snapshot().isAuthorized
  }

  /// Returns the current permission label.
  func permissionState() -> String {
    snapshot().permissionState
  }

  /// Handles one location authorization change.
  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    guard let session = lifecycle.currentSession() else { return }
    let status = manager.authorizationStatus

    Task { @MainActor [weak self, weak session] in
      guard let self, let session, self.lifecycle.isCurrent(session) else { return }

      self.setAuthorizationStatus(status)
      self.logger.info(
        "\(self.componentName) authorization changed",
        .field("status", self.permissionState())
      )
      self.handleAuthorizationStateChange(status, session: session)
      self.lifecycle.notify(session)
    }
  }

  /// Requests location access when the current generation still owns the flow.
  private func requestAccessIfNeeded(for session: AuthorizationLifecycle.Session) {
    guard lifecycle.isCurrent(session) else { return }

    let status = locationManager.authorizationStatus
    setAuthorizationStatus(status)

    logger.info(
      "\(componentName) access status",
      .field("status", permissionState()),
    )

    switch status {
    case .authorized, .authorizedAlways, .authorizedWhenInUse:
      lifecycle.resetRetry(for: session)
      restoreAccessoryModeIfNeeded(for: session)
      logger.info(
        "\(componentName) access already granted",
        .field("status", permissionState())
      )
      lifecycle.notify(session)

    case .notDetermined:
      prepareAuthorizationPromptIfNeeded(for: session)
      logger.info(
        "requesting \(componentName) when-in-use access",
        .field("status", permissionState())
      )
      locationManager.requestWhenInUseAuthorization()
      scheduleRetry(for: session)

    case .denied, .restricted:
      lifecycle.resetRetry(for: session)
      restoreAccessoryModeIfNeeded(for: session)
      logger.warn(
        "\(componentName) access unavailable",
        .field("status", permissionState())
      )

    @unknown default:
      lifecycle.resetRetry(for: session)
      restoreAccessoryModeIfNeeded(for: session)
      logger.warn(
        "\(componentName) access status unknown",
        .field("raw", status.rawValue),
      )
    }
  }

  /// Sets authorization status.
  private func setAuthorizationStatus(_ status: CLAuthorizationStatus) {
    authorizationStatus.withLock { $0 = status }
  }

  /// Returns the current authorization status.
  private func currentAuthorizationStatus() -> CLAuthorizationStatus {
    authorizationStatus.withLock { $0 }
  }

  /// Updates retry scheduling for one changed authorization state.
  private func handleAuthorizationStateChange(
    _ status: CLAuthorizationStatus,
    session: AuthorizationLifecycle.Session
  ) {
    switch status {
    case .authorized, .authorizedAlways, .authorizedWhenInUse, .denied, .restricted:
      lifecycle.resetRetry(for: session)
      restoreAccessoryModeIfNeeded(for: session)

    case .notDetermined:
      scheduleRetry(for: session)

    @unknown default:
      lifecycle.resetRetry(for: session)
    }
  }

  /// Schedules one follow-up authorization check while access is unresolved.
  private func scheduleRetry(for session: AuthorizationLifecycle.Session) {
    lifecycle.scheduleRetry(for: session) { [weak self] session in
      self?.requestAccessIfNeeded(for: session)
    }
  }

  /// Temporarily prepares the host so macOS can surface the permission prompt.
  private func prepareAuthorizationPromptIfNeeded(for session: AuthorizationLifecycle.Session) {
    guard lifecycle.isCurrent(session) else { return }

    let owner = ObjectIdentifier(session)
    let shouldPrepare = promptOwner.withLock { currentOwner -> Bool in
      guard currentOwner == nil else { return false }
      currentOwner = owner
      return true
    }
    guard shouldPrepare else { return }

    logger.info(
      "\(componentName) preparing authorization prompt",
      .field("presented", true),
    )

    Task { @MainActor [weak self, weak promptPresenter, weak session] in
      guard let self, let session, self.lifecycle.isCurrent(session) else { return }

      self.promptOwner.withLock { currentOwner in
        guard currentOwner == owner else { return }
        promptPresenter?.preparePrompt()
      }
    }
  }

  /// Restores host UI after the location permission state resolves.
  private func restoreAccessoryModeIfNeeded(for session: AuthorizationLifecycle.Session) {
    let owner = ObjectIdentifier(session)
    let shouldRestore = promptOwner.withLock { currentOwner -> Bool in
      guard currentOwner == owner else { return false }
      currentOwner = nil
      return true
    }
    guard shouldRestore else { return }

    logger.info(
      "\(componentName) restoring UI after authorization prompt",
      .field("presented", false),
    )

    Task { @MainActor [weak self, weak promptPresenter] in
      guard let self else { return }

      self.promptOwner.withLock { currentOwner in
        guard currentOwner == nil else { return }
        promptPresenter?.restoreUI()
      }
    }
  }
}
