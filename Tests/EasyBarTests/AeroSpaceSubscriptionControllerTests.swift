import Foundation
import XCTest

@testable import EasyBarKit
@testable import EasyBarShared

final class AeroSpaceSubscriptionControllerTests: XCTestCase {
  private final class FakeSubscriptionLauncher: AeroSpaceSubscriptionLaunching, @unchecked Sendable {
    private let lock = NSLock()
    private var subscriptions: [FakeSubscriptionSession] = []
    private var available = true

    func makeSubscription() -> AeroSpaceSubscriptionSession {
      lock.withLock {
        let subscription = FakeSubscriptionSession(failStart: !available)
        subscriptions.append(subscription)
        return subscription
      }
    }

    func setAvailable(_ available: Bool) {
      lock.withLock {
        self.available = available
      }
    }

    var launchCount: Int {
      lock.withLock { subscriptions.count }
    }

    func subscription(at index: Int) -> FakeSubscriptionSession? {
      lock.withLock {
        guard subscriptions.indices.contains(index) else { return nil }
        return subscriptions[index]
      }
    }
  }

  private final class FakeSubscriptionSession: AeroSpaceSubscriptionSession, @unchecked Sendable {
    private struct StartError: Error {}

    private let lock = NSLock()
    private let failStart: Bool
    private var eventFrameHandler: (@Sendable (Data) -> Void)?
    private var disconnectHandler: (@Sendable (AeroSpaceSubscriptionSession, String?) -> Void)?
    private var didStart = false
    private var didStop = false
    private var didInvalidate = false

    init(failStart: Bool = false) {
      self.failStart = failStart
    }

    var started: Bool { lock.withLock { didStart } }
    var stopped: Bool { lock.withLock { didStop } }
    var invalidated: Bool { lock.withLock { didInvalidate } }

    func start(
      onEventFrame: @escaping @Sendable (Data) -> Void,
      onDisconnect: @escaping @Sendable (AeroSpaceSubscriptionSession, String?) -> Void
    ) throws {
      if failStart { throw StartError() }
      lock.withLock {
        didStart = true
        eventFrameHandler = onEventFrame
        disconnectHandler = onDisconnect
      }
    }

    func stop() {
      lock.withLock {
        didStop = true
        clearHandlers()
      }
    }

    func invalidate() {
      lock.withLock {
        didInvalidate = true
        clearHandlers()
      }
    }

    func emitOutputLine(_ line: String) {
      let handler = lock.withLock { eventFrameHandler }
      handler?(Data(line.utf8))
    }

    func terminate(status: Int32) {
      let handler = lock.withLock {
        () -> (@Sendable (AeroSpaceSubscriptionSession, String?) -> Void)? in
        let handler = disconnectHandler
        disconnectHandler = nil
        return handler
      }
      handler?(self, status == 0 ? nil : "socket error \(status)")
    }

    private func clearHandlers() {
      eventFrameHandler = nil
      disconnectHandler = nil
    }
  }

  private final class RecordingReconnectScheduler: AeroSpaceReconnectScheduling, @unchecked Sendable {
    private let lock = NSLock()
    private var actions: [@Sendable () -> Void] = []
    private(set) var cancelCount = 0
    private(set) var resetDelayCount = 0

    var scheduledCount: Int {
      lock.withLock { actions.count }
    }

    func schedule(_ action: @escaping @Sendable () -> Void) {
      lock.withLock {
        actions.append(action)
      }
    }

    func cancel() {
      lock.withLock {
        cancelCount += 1
        actions.removeAll()
      }
    }

    func resetDelay() {
      lock.withLock {
        resetDelayCount += 1
      }
    }

    func runNextScheduledAction() -> Bool {
      let action = lock.withLock { () -> (@Sendable () -> Void)? in
        guard !actions.isEmpty else { return nil }
        return actions.removeFirst()
      }

      guard let action else { return false }
      action()
      return true
    }
  }

  func testReconnectsWhenSubscriptionExits() throws {
    let logger = Self.makeLogger()
    let launcher = FakeSubscriptionLauncher()
    let scheduler = RecordingReconnectScheduler()
    let controller = Self.makeController(
      logger: logger,
      launcher: launcher,
      scheduler: scheduler
    )

    controller.start()
    defer { controller.stop() }

    XCTAssertEqual(launcher.launchCount, 1)
    XCTAssertTrue(waitUntil { launcher.subscription(at: 0)?.started == true })
    launcher.subscription(at: 0)?.terminate(status: 3)

    XCTAssertEqual(scheduler.scheduledCount, 1)
    XCTAssertTrue(scheduler.runNextScheduledAction())
    XCTAssertEqual(launcher.launchCount, 2)
  }

  func testReconnectsWhenSocketAppearsAfterStartup() throws {
    let logger = Self.makeLogger()
    let launcher = FakeSubscriptionLauncher()
    let scheduler = RecordingReconnectScheduler()
    let controller = Self.makeController(
      logger: logger,
      launcher: launcher,
      scheduler: scheduler
    )

    launcher.setAvailable(false)
    controller.start()
    defer { controller.stop() }

    XCTAssertEqual(launcher.launchCount, 1)
    XCTAssertTrue(waitUntil { scheduler.scheduledCount == 1 })

    launcher.setAvailable(true)
    XCTAssertTrue(scheduler.runNextScheduledAction())
    XCTAssertTrue(waitUntil { launcher.launchCount == 2 })
    XCTAssertTrue(waitUntil { launcher.subscription(at: 1)?.started == true })
  }

  func testSchedulesReconnectForEachCrash() throws {
    let logger = Self.makeLogger()
    let launcher = FakeSubscriptionLauncher()
    let scheduler = RecordingReconnectScheduler()
    let controller = Self.makeController(
      logger: logger,
      launcher: launcher,
      scheduler: scheduler
    )

    controller.start()
    defer { controller.stop() }

    XCTAssertEqual(launcher.launchCount, 1)
    XCTAssertTrue(waitUntil { launcher.subscription(at: 0)?.started == true })
    launcher.subscription(at: 0)?.terminate(status: 3)
    XCTAssertEqual(scheduler.scheduledCount, 1)

    XCTAssertTrue(scheduler.runNextScheduledAction())
    XCTAssertEqual(launcher.launchCount, 2)
    XCTAssertTrue(waitUntil { launcher.subscription(at: 1)?.started == true })
    launcher.subscription(at: 1)?.terminate(status: 3)
    XCTAssertEqual(scheduler.scheduledCount, 1)

    XCTAssertTrue(scheduler.runNextScheduledAction())
    XCTAssertEqual(launcher.launchCount, 3)
  }

  func testResetsReconnectBackoffAfterEventLine() throws {
    let logger = Self.makeLogger()
    let launcher = FakeSubscriptionLauncher()
    let scheduler = RecordingReconnectScheduler()
    let controller = Self.makeController(
      logger: logger,
      launcher: launcher,
      scheduler: scheduler
    )

    controller.start()
    defer { controller.stop() }

    XCTAssertEqual(launcher.launchCount, 1)
    XCTAssertTrue(waitUntil { launcher.subscription(at: 0)?.started == true })
    launcher.subscription(at: 0)?.emitOutputLine(#"{"_event":"focused-workspace-changed"}"#)

    XCTAssertEqual(scheduler.resetDelayCount, 1)
    launcher.subscription(at: 0)?.terminate(status: 3)
    XCTAssertEqual(scheduler.scheduledCount, 1)

    XCTAssertTrue(scheduler.runNextScheduledAction())
    XCTAssertEqual(launcher.launchCount, 2)
  }

  func testStopCancelsPendingReconnect() throws {
    let logger = Self.makeLogger()
    let launcher = FakeSubscriptionLauncher()
    let scheduler = RecordingReconnectScheduler()
    let controller = Self.makeController(
      logger: logger,
      launcher: launcher,
      scheduler: scheduler
    )

    controller.start()
    XCTAssertEqual(launcher.launchCount, 1)
    XCTAssertTrue(waitUntil { launcher.subscription(at: 0)?.started == true })
    launcher.subscription(at: 0)?.terminate(status: 3)
    XCTAssertEqual(scheduler.scheduledCount, 1)

    controller.stop()

    XCTAssertEqual(scheduler.cancelCount, 2)
    XCTAssertFalse(scheduler.runNextScheduledAction())
    XCTAssertEqual(launcher.launchCount, 1)
  }

  private static func makeController(
    logger: ProcessLogger,
    launcher: FakeSubscriptionLauncher,
    scheduler: RecordingReconnectScheduler
  ) -> AeroSpaceSubscriptionController {
    AeroSpaceSubscriptionController(
      logger: logger,
      subscriptionLauncher: launcher,
      reconnectScheduler: scheduler,
      handleEvent: { _ in }
    )
  }

  private static func makeLogger() -> ProcessLogger {
    ProcessLogger(
      label: "easybar.app.services.aerospace.subscription.tests",
      minimumLevel: .error,
      outputStream: nil,
      errorStream: nil
    )
  }

  private func waitUntil(
    timeout: TimeInterval = 1,
    condition: () -> Bool
  ) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if condition() { return true }
      usleep(1_000)
    }
    return condition()
  }
}
