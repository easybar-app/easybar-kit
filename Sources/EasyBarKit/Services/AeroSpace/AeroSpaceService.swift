import Combine
import EasyBarShared
import Foundation

/// Loads workspace and focused-app state from AeroSpace.
///
/// Widgets can register themselves as consumers so AeroSpace refresh work only
/// runs when at least one native widget depends on that state.
final class AeroSpaceService: ObservableObject, @unchecked Sendable {
  /// Published workspace list used by spaces widgets.
  @Published private(set) var spaces: [SpaceItem] = []
  /// Resolved focused app used by `FrontAppNativeWidget`.
  @Published private(set) var focusedApp: SpaceApp?

  /// Stable id derived from the canonical focused application state.
  var focusedAppID: String? { focusedApp?.id }

  /// Resolved layout mode used by `AeroSpaceModeNativeWidget`.
  @Published private(set) var focusedLayoutMode: AeroSpaceLayoutMode = .unknown

  /// Whether the published snapshot is current or retained after an error.
  @Published private(set) var snapshotStatus: AeroSpaceSnapshotStatus = .unavailable(
    message: "not loaded"
  )

  /// Locked service coordination state.
  struct CoordinationState {
    /// Registered widget consumers.
    var consumers: [String: @MainActor @Sendable () -> Void] = [:]
    /// Whether the service lifecycle is running.
    var running = false
    /// Whether AeroSpace observation is active for at least one consumer.
    var active = false
    /// Generation used to ignore stale lifecycle work.
    var generation: UInt64 = 0
    /// Sequence used to ensure only the newest refresh can publish.
    var refreshSequence = AeroSpaceRefreshSequence()
    /// Token reserved for the queued or running refresh.
    var pendingRefreshToken: AeroSpaceRefreshToken?
    /// Cancellable refresh task that owns current CLI commands.
    var refreshTask: Task<Void, Never>?
    /// Revision used to prevent full snapshots from overwriting newer fast focus results.
    var focusedStateRevision: UInt64 = 0
    /// Token reserved for the newest focused-window query.
    var pendingFocusedStateToken: AeroSpaceFocusedStateToken?
    /// Cancellable focused-window query task.
    var focusedStateTask: Task<Void, Never>?
    /// Sequence used to own optimistic workspace-focus mutations.
    var workspaceFocusRequestID: UInt64 = 0
    /// Current optimistic workspace-focus request.
    var pendingWorkspaceFocusToken: AeroSpaceWorkspaceFocusToken?
    /// Cancellable workspace-focus command task.
    var workspaceFocusTask: Task<Void, Never>?

    /// Whether the running service has active observation work to perform.
    var acceptsWork: Bool {
      running && active && !consumers.isEmpty
    }

    /// Whether the first consumer can activate observation.
    var canActivate: Bool {
      running && !active && !consumers.isEmpty
    }
  }

  /// Logger used for AeroSpace diagnostics.
  let logger: ProcessLogger
  let eventHub: EventHub
  /// Runner for AeroSpace CLI commands.
  let commandRunner: any AeroSpaceCommandRunning
  /// Optional test-provided subscription controller.
  private let subscriptionControllerOverride: (any AeroSpaceSubscriptionControlling)?
  /// Long-lived AeroSpace event subscription.
  lazy var subscriptionController: any AeroSpaceSubscriptionControlling = {
    if let subscriptionControllerOverride {
      return subscriptionControllerOverride
    }
    return AeroSpaceSubscriptionController(
      logger: logger.child("subscribe"),
      handleEvent: { [weak self] event in
        self?.handleAeroSpaceSubscriptionEvent(event)
      }
    )
  }()
  /// Debounces complete snapshots so focus bursts produce one full state read.
  lazy var subscriptionRefreshScheduler = DebouncedActionScheduler(
    label: "aerospace subscription refresh",
    delay: TimeInterval(AeroSpaceSubscriptionEvent.fullSnapshotDebounceNanoseconds)
      / 1_000_000_000,
    logger: logger
  )
  /// Retries failed version checks and snapshots without requiring another external event.
  let refreshRetryScheduler: any AeroSpaceReconnectScheduling
  /// Shares one in-flight version check and caches successes per lifecycle generation.
  let versionValidationCache: AeroSpaceVersionValidationCache
  /// Current locked coordination state.
  let coordination = LockedState(CoordinationState())

  /// Replaces the published workspace state from a main-actor service operation.
  @MainActor
  func replaceSpaces(_ spaces: [SpaceItem]) {
    self.spaces = spaces
  }

  /// Replaces the fast focused-app state from a main-actor service operation.
  @MainActor
  func replaceFocusedState(
    app: SpaceApp?,
    layoutMode: AeroSpaceLayoutMode
  ) {
    focusedApp = app
    focusedLayoutMode = layoutMode
  }

  /// Replaces the published snapshot health from a main-actor service operation.
  @MainActor
  func replaceSnapshotStatus(_ status: AeroSpaceSnapshotStatus) {
    snapshotStatus = status
  }

  /// Creates the shared AeroSpace service.
  init(
    logger: ProcessLogger,
    eventHub: EventHub,
    commandRunner: (any AeroSpaceCommandRunning)? = nil,
    subscriptionController: (any AeroSpaceSubscriptionControlling)? = nil,
    refreshRetryScheduler: (any AeroSpaceReconnectScheduling)? = nil
  ) {
    self.logger = logger
    self.eventHub = eventHub
    let resolvedCommandRunner =
      commandRunner ?? AeroSpaceCommandRunner(logger: logger.child("commands"))
    self.commandRunner = resolvedCommandRunner
    self.subscriptionControllerOverride = subscriptionController
    self.refreshRetryScheduler =
      refreshRetryScheduler
      ?? BackoffScheduler(
        label: "aerospace refresh retry",
        delays: [0.5, 1, 2, 5, 10],
        logger: logger,
        logLevel: .debug
      )
    self.versionValidationCache = AeroSpaceVersionValidationCache(
      commandRunner: resolvedCommandRunner,
      logger: logger
    )
  }
}
