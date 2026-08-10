import Foundation
import XCTest

@testable import EasyBarKit
@testable import EasyBarShared

@MainActor
final class AeroSpaceServiceRecoveryTests: XCTestCase {
  private final class ScriptedRunner: AeroSpaceCommandRunning, @unchecked Sendable {
    private struct State {
      var versionFailuresRemaining = 0
      var snapshotFailuresEnabled = false
      var workspaceName = "1"
      var workspaceNames = ["1"]
      var workspaceCommandSucceeds = true
      var focusedAppName: String?
      var focusedAppPath = ""
      var focusedLayout = "tiles"
      var snapshotDelayNanoseconds: UInt64 = 0
      var versionCallCount = 0
      var workspaceCallCount = 0
      var workspaceCommandCallCount = 0
      var focusedWindowCallCount = 0
      var activeCalls = 0
      var maximumActiveCalls = 0
      var cancellationCount = 0
    }

    private let state = LockedState(State())

    func run(arguments: [String]) async -> String? {
      state.withLock { state in
        state.activeCalls += 1
        state.maximumActiveCalls = max(state.maximumActiveCalls, state.activeCalls)
      }
      defer {
        state.withLock { state in state.activeCalls -= 1 }
      }

      if arguments.first == "workspace", arguments.count == 2 {
        return state.withLock { state in
          state.workspaceCommandCallCount += 1
          guard state.workspaceCommandSucceeds else { return nil }
          state.workspaceName = arguments[1]
          return ""
        }
      }

      if arguments == ["--version"] {
        let shouldFail = state.withLock { state -> Bool in
          state.versionCallCount += 1
          guard state.versionFailuresRemaining > 0 else { return false }
          state.versionFailuresRemaining -= 1
          return true
        }
        if shouldFail { return nil }
        return Self.supportedVersionOutput
      }

      let delay = state.withLock(\.snapshotDelayNanoseconds)
      if delay > 0 {
        do {
          try await Task.sleep(nanoseconds: delay)
        } catch {
          state.withLock { $0.cancellationCount += 1 }
          return nil
        }
      }
      guard !Task.isCancelled else {
        state.withLock { $0.cancellationCount += 1 }
        return nil
      }

      let snapshotState = state.withLock { state in
        (
          shouldFail: state.snapshotFailuresEnabled,
          workspaceName: state.workspaceName,
          workspaceNames: state.workspaceNames
        )
      }
      if snapshotState.shouldFail { return nil }

      switch arguments.first {
      case "list-workspaces":
        state.withLock { $0.workspaceCallCount += 1 }
        let rows = snapshotState.workspaceNames.map { name in
          let focused = name == snapshotState.workspaceName ? "true" : "false"
          return
            #"{"workspace":"\#(name)","workspace-is-focused":\#(focused),"workspace-is-visible":true}"#
        }
        return "[\(rows.joined(separator: ","))]"
      case "list-windows":
        if arguments.contains("--focused") {
          return state.withLock { state in
            state.focusedWindowCallCount += 1
            guard let name = state.focusedAppName else { return "[]" }
            return
              #"[{"workspace":"\#(state.workspaceName)","app-name":"\#(name)","app-bundle-path":"\#(state.focusedAppPath)","window-layout":"\#(state.focusedLayout)"}]"#
          }
        }
        return "[]"
      default:
        return nil
      }
    }

    func failNextVersionChecks(_ count: Int) {
      state.withLock { $0.versionFailuresRemaining = count }
    }

    func setSnapshotFailuresEnabled(_ enabled: Bool) {
      state.withLock { $0.snapshotFailuresEnabled = enabled }
    }

    func setWorkspaceName(_ name: String) {
      state.withLock { state in
        state.workspaceName = name
        state.workspaceNames = [name]
      }
    }

    func setWorkspaces(_ names: [String], focused name: String) {
      state.withLock { state in
        state.workspaceNames = names
        state.workspaceName = name
      }
    }

    func setWorkspaceCommandSucceeds(_ succeeds: Bool) {
      state.withLock { $0.workspaceCommandSucceeds = succeeds }
    }

    func setFocusedApp(name: String, path: String, layout: String = "tiles") {
      state.withLock { state in
        state.focusedAppName = name
        state.focusedAppPath = path
        state.focusedLayout = layout
      }
    }

    func setSnapshotDelayNanoseconds(_ value: UInt64) {
      state.withLock { $0.snapshotDelayNanoseconds = value }
    }

    var versionCallCount: Int { state.withLock(\.versionCallCount) }
    var workspaceCallCount: Int { state.withLock(\.workspaceCallCount) }
    var workspaceCommandCallCount: Int { state.withLock(\.workspaceCommandCallCount) }
    var focusedWindowCallCount: Int { state.withLock(\.focusedWindowCallCount) }
    var maximumActiveCalls: Int { state.withLock(\.maximumActiveCalls) }
    var cancellationCount: Int { state.withLock(\.cancellationCount) }

    private static let supportedVersionOutput =
      """
      aerospace CLI client version: 0.21.1-Beta
      AeroSpace.app server version: 0.21.1-Beta
      """
  }

  private final class RecordingSubscriptionController: AeroSpaceSubscriptionControlling,
    @unchecked Sendable
  {
    private struct State {
      var starts = 0
      var stops = 0
    }

    private let state = LockedState(State())

    func start() { state.withLock { $0.starts += 1 } }
    func stop() { state.withLock { $0.stops += 1 } }

    var startCount: Int { state.withLock(\.starts) }
  }

  private final class RecordingRetryScheduler: AeroSpaceReconnectScheduling,
    @unchecked Sendable
  {
    private struct State {
      var actions: [@Sendable () -> Void] = []
      var resetCount = 0
    }

    private let state = LockedState(State())

    func schedule(_ action: @escaping @Sendable () -> Void) {
      state.withLock { state in
        guard state.actions.isEmpty else { return }
        state.actions.append(action)
      }
    }

    func cancel() {
      state.withLock { state in
        state.actions.removeAll()
        state.resetCount += 1
      }
    }

    func resetDelay() {
      state.withLock { $0.resetCount += 1 }
    }

    var scheduledCount: Int { state.withLock { $0.actions.count } }

    @discardableResult
    func runNext() -> Bool {
      let action = state.withLock { state -> (@Sendable () -> Void)? in
        guard !state.actions.isEmpty else { return nil }
        return state.actions.removeFirst()
      }
      guard let action else { return false }
      action()
      return true
    }
  }

  func testRetainsLastKnownGoodSnapshotAfterCommandFailure() async {
    let runner = ScriptedRunner()
    let retry = RecordingRetryScheduler()
    let service = makeService(runner: runner, retry: retry)

    service.start()
    service.registerConsumer("test") {}
    defer { service.stop() }

    let becameCurrent = await waitUntil { service.snapshotStatus == .current }
    XCTAssertTrue(becameCurrent)
    XCTAssertEqual(service.spaces.map(\.name), ["1"])

    runner.setSnapshotFailuresEnabled(true)
    service.refresh()

    let becameStale = await waitUntil {
      if case .stale = service.snapshotStatus { return true }
      return false
    }
    XCTAssertTrue(becameStale)
    XCTAssertEqual(service.spaces.map(\.name), ["1"])
    XCTAssertEqual(retry.scheduledCount, 1)
  }

  func testRetriesTransientVersionFailureWithoutRestartingService() async {
    let runner = ScriptedRunner()
    runner.failNextVersionChecks(1)
    let retry = RecordingRetryScheduler()
    let subscription = RecordingSubscriptionController()
    let service = makeService(
      runner: runner,
      retry: retry,
      subscription: subscription
    )

    service.start()
    service.registerConsumer("test") {}
    defer { service.stop() }

    let retryScheduled = await waitUntil { retry.scheduledCount == 1 }
    XCTAssertTrue(retryScheduled)
    XCTAssertEqual(runner.versionCallCount, 1)
    XCTAssertEqual(subscription.startCount, 1)

    XCTAssertTrue(retry.runNext())
    let recovered = await waitUntil { service.snapshotStatus == .current }
    XCTAssertTrue(recovered)
    XCTAssertEqual(runner.versionCallCount, 2)
    XCTAssertEqual(service.spaces.map(\.name), ["1"])
  }

  func testBurstRefreshesCancelSupersededSnapshotCommands() async {
    let runner = ScriptedRunner()
    runner.setSnapshotDelayNanoseconds(150_000_000)
    let service = makeService(runner: runner, retry: RecordingRetryScheduler())

    service.start()
    service.registerConsumer("test") {}
    defer { service.stop() }

    let versionChecked = await waitUntil { runner.versionCallCount == 1 }
    XCTAssertTrue(versionChecked)

    for index in 2...6 {
      runner.setWorkspaceName(String(index))
      service.refresh()
      try? await Task.sleep(nanoseconds: 10_000_000)
    }

    let latestPublished = await waitUntil(timeout: 2) {
      service.snapshotStatus == .current
        && service.spaces.map(\.name) == ["6"]
    }
    XCTAssertTrue(latestPublished)
    XCTAssertEqual(service.spaces.map(\.name), ["6"])
    XCTAssertGreaterThan(runner.cancellationCount, 0)
    XCTAssertLessThanOrEqual(runner.maximumActiveCalls, 2)
    XCTAssertEqual(runner.versionCallCount, 1)
  }

  func testFailedWorkspaceFocusRestoresPreviousPublishedFocus() async {
    let runner = ScriptedRunner()
    runner.setWorkspaces(["1", "2"], focused: "1")
    let service = makeService(runner: runner, retry: RecordingRetryScheduler())
    var updateCount = 0

    service.start()
    service.registerConsumer("test") { updateCount += 1 }
    defer { service.stop() }

    let initialSnapshotLoaded = await waitUntil { service.snapshotStatus == .current }
    XCTAssertTrue(initialSnapshotLoaded)
    runner.setWorkspaceCommandSucceeds(false)

    service.focusWorkspace("2")
    XCTAssertEqual(service.spaces.first(where: { $0.isFocused })?.name, "2")

    let rolledBack = await waitUntil {
      service.spaces.first(where: { $0.isFocused })?.name == "1"
    }
    XCTAssertTrue(rolledBack)
    XCTAssertEqual(runner.workspaceCommandCallCount, 1)
    XCTAssertGreaterThanOrEqual(updateCount, 3)
  }

  func testSuccessfulWorkspaceFocusRefreshesCanonicalState() async {
    let runner = ScriptedRunner()
    runner.setWorkspaces(["1", "2"], focused: "1")
    let service = makeService(runner: runner, retry: RecordingRetryScheduler())

    service.start()
    service.registerConsumer("test") {}
    defer { service.stop() }

    let initialSnapshotLoaded = await waitUntil { service.snapshotStatus == .current }
    XCTAssertTrue(initialSnapshotLoaded)

    service.focusWorkspace("2")

    let focused = await waitUntil {
      service.spaces.first(where: { $0.isFocused })?.name == "2"
        && runner.workspaceCommandCallCount == 1
        && runner.workspaceCallCount >= 2
    }
    XCTAssertTrue(focused)
  }

  func testFocusEventPublishesFastStateBeforeDebouncedFullSnapshot() async {
    let runner = ScriptedRunner()
    runner.setFocusedApp(name: "Initial", path: "/Applications/Initial.app")
    let service = makeService(runner: runner, retry: RecordingRetryScheduler())

    service.start()
    service.registerConsumer("test") {}
    defer { service.stop() }

    let initialSnapshotLoaded = await waitUntil { service.snapshotStatus == .current }
    XCTAssertTrue(initialSnapshotLoaded)
    let initialWorkspaceCalls = runner.workspaceCallCount

    runner.setFocusedApp(name: "Next", path: "/Applications/Next.app", layout: "floating")
    service.handleAeroSpaceSubscriptionEvent(
      AeroSpaceSubscriptionEvent(name: AeroSpaceSubscriptionEvent.Name.focusChanged)
    )

    let fastStatePublished = await waitUntil(timeout: 0.1) {
      service.focusedApp?.name == "Next"
        && service.focusedLayoutMode == .floating
    }
    XCTAssertTrue(fastStatePublished)
    XCTAssertEqual(runner.workspaceCallCount, initialWorkspaceCalls)

    let fullSnapshotRan = await waitUntil(timeout: 0.5) {
      runner.workspaceCallCount == initialWorkspaceCalls + 1
    }
    XCTAssertTrue(fullSnapshotRan)
    XCTAssertGreaterThanOrEqual(runner.focusedWindowCallCount, 3)
  }

  func testWorkspaceEventPublishesFocusBeforeImmediateFullSnapshotCompletes() async {
    let runner = ScriptedRunner()
    runner.setWorkspaces(["1", "2"], focused: "1")
    let service = makeService(runner: runner, retry: RecordingRetryScheduler())

    service.start()
    service.registerConsumer("test") {}
    defer { service.stop() }

    let initialSnapshotLoaded = await waitUntil { service.snapshotStatus == .current }
    XCTAssertTrue(initialSnapshotLoaded)

    runner.setSnapshotDelayNanoseconds(150_000_000)
    runner.setWorkspaces(["1", "2"], focused: "2")
    service.handleAeroSpaceSubscriptionEvent(
      AeroSpaceSubscriptionEvent(
        name: AeroSpaceSubscriptionEvent.Name.focusedWorkspaceChanged,
        workspace: "2"
      )
    )

    let optimisticFocusPublished = await waitUntil(timeout: 0.1) {
      service.spaces.first(where: { $0.isFocused })?.name == "2"
    }
    XCTAssertTrue(optimisticFocusPublished)

    let canonicalSnapshotCompleted = await waitUntil(timeout: 1) {
      service.snapshotStatus == .current
        && runner.workspaceCallCount >= 2
        && runner.focusedWindowCallCount >= 2
        && service.spaces.first(where: { $0.isFocused })?.name == "2"
    }
    XCTAssertTrue(canonicalSnapshotCompleted)
  }

  private func makeService(
    runner: ScriptedRunner,
    retry: RecordingRetryScheduler,
    subscription: RecordingSubscriptionController = RecordingSubscriptionController()
  ) -> AeroSpaceService {
    let logger = ProcessLogger(
      label: "easybar.aerospace.service.tests",
      minimumLevel: .error,
      outputStream: nil,
      errorStream: nil
    )
    let eventHub = EventHub(logger: logger, enqueueLuaEvent: { _ in })
    return AeroSpaceService(
      logger: logger,
      eventHub: eventHub,
      commandRunner: runner,
      subscriptionController: subscription,
      refreshRetryScheduler: retry
    )
  }

  private func waitUntil(
    timeout: TimeInterval = 1,
    condition: @escaping @MainActor () -> Bool
  ) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if condition() { return true }
      try? await Task.sleep(nanoseconds: 5_000_000)
    }
    return condition()
  }
}
