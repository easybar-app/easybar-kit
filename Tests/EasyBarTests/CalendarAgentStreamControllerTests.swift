import Foundation
import XCTest

@testable import EasyBarKit
@testable import EasyBarShared

@MainActor
final class CalendarAgentStreamControllerTests: XCTestCase {
  func testInvalidRequestRetainsSnapshotAndWaitsForChangedRequest() async throws {
    let logger = ProcessLogger(
      label: "calendar.stream.tests",
      minimumLevel: .error,
      outputStream: nil,
      errorStream: nil
    )
    let temporaryDirectory = URL(fileURLWithPath: "/tmp", isDirectory: true)
      .appendingPathComponent("eb-calendar-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: temporaryDirectory,
      withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let socketPath = temporaryDirectory.appendingPathComponent("agent.sock").path
    let request = LockedState(Self.makeRequest(marker: "valid"))
    let requestCount = LockedState(0)
    let appliedSnapshots = LockedState(0)
    let clearedSnapshots = LockedState(0)

    let server = LineSocketServerTransport<
      Void, CalendarAgentRequest, CalendarAgentMessage
    >(
      socketPath: socketPath,
      serverLabel: "calendar stream tests",
      logger: logger
    )
    XCTAssertTrue(
      server.start { fd, request in
        requestCount.withLock { $0 += 1 }

        if request.query?.emptyText == "invalid" {
          _ = server.send(
            CalendarAgentMessage(
              kind: .error,
              requestID: request.requestID,
              errorCode: .invalidRequest,
              message: "invalid request"
            ),
            to: fd
          )
          return .close
        }

        server.addSubscriber((), for: fd)
        _ = server.send(
          CalendarAgentMessage(
            kind: .snapshot,
            requestID: request.requestID,
            snapshot: Self.makeSnapshot()
          ),
          to: fd
        )
        return .keepOpen
      }
    )
    defer { server.stop() }

    let eventHub = EventHub(logger: logger, enqueueLuaEvent: { _ in })
    let eventRelay = CalendarAgentEventRelay(logger: logger, eventHub: eventHub)
    let controller = CalendarAgentStreamController(
      label: "calendar stream test client",
      socketPath: { socketPath },
      makeRequest: { request.withLock { $0 } },
      applySnapshot: { _ in appliedSnapshots.withLock { $0 += 1 } },
      clearState: { clearedSnapshots.withLock { $0 += 1 } },
      eventRelay: eventRelay,
      logger: logger
    )
    controller.start(enabled: true)
    defer { controller.stop() }

    try await waitUntil("initial snapshot") {
      appliedSnapshots.withLock { $0 == 1 }
    }

    request.withLock { $0 = Self.makeRequest(marker: "invalid") }
    controller.refresh()

    try await waitUntil("invalid request disconnect") {
      requestCount.withLock { $0 == 2 } && !controller.isConnected
    }
    XCTAssertEqual(clearedSnapshots.withLock { $0 }, 0)

    XCTAssertFalse(controller.refresh())
    XCTAssertEqual(requestCount.withLock { $0 }, 2)
    XCTAssertEqual(clearedSnapshots.withLock { $0 }, 0)

    request.withLock { $0 = Self.makeRequest(marker: "changed") }
    controller.refresh()

    try await waitUntil("changed request snapshot") {
      requestCount.withLock { $0 == 3 } && appliedSnapshots.withLock { $0 == 2 }
    }
    XCTAssertEqual(clearedSnapshots.withLock { $0 }, 0)
  }

  func testStaleInvalidRequestDoesNotBlockLatestSubscription() async throws {
    let logger = ProcessLogger(
      label: "calendar.stream.correlation.tests",
      minimumLevel: .error,
      outputStream: nil,
      errorStream: nil
    )
    let temporaryDirectory = URL(fileURLWithPath: "/tmp", isDirectory: true)
      .appendingPathComponent("eb-calendar-correlation-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: temporaryDirectory,
      withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let socketPath = temporaryDirectory.appendingPathComponent("agent.sock").path
    let currentRequest = LockedState(Self.makeRequest(marker: "initial"))
    let appliedSnapshots = LockedState(0)
    let requestCount = LockedState(0)
    let releaseStaleResponse = DispatchSemaphore(value: 0)
    defer { releaseStaleResponse.signal() }

    let server = LineSocketServerTransport<
      Void, CalendarAgentRequest, CalendarAgentMessage
    >(
      socketPath: socketPath,
      serverLabel: "calendar correlation tests",
      logger: logger
    )
    XCTAssertTrue(
      server.start { fd, request in
        requestCount.withLock { $0 += 1 }
        let marker = request.query?.emptyText

        if marker == "stale" {
          let requestID = request.requestID
          DispatchQueue.global(qos: .userInitiated).async {
            releaseStaleResponse.wait()
            _ = server.send(
              CalendarAgentMessage(
                kind: .error,
                requestID: requestID,
                errorCode: .invalidRequest,
                message: "stale invalid request"
              ),
              to: fd
            )
            _ = server.removeSubscriber(fd: fd)
          }
          return .keepOpen
        }

        server.addSubscriber((), for: fd)
        _ = server.send(
          CalendarAgentMessage(
            kind: .snapshot,
            requestID: request.requestID,
            snapshot: Self.makeSnapshot()
          ),
          to: fd
        )
        return .keepOpen
      }
    )
    defer { server.stop() }

    let eventHub = EventHub(logger: logger, enqueueLuaEvent: { _ in })
    let controller = CalendarAgentStreamController(
      label: "calendar correlation test client",
      socketPath: { socketPath },
      makeRequest: { currentRequest.withLock { $0 } },
      applySnapshot: { _ in appliedSnapshots.withLock { $0 += 1 } },
      eventRelay: CalendarAgentEventRelay(logger: logger, eventHub: eventHub),
      logger: logger
    )
    controller.start(enabled: true)
    defer { controller.stop() }

    try await waitUntil("initial correlated snapshot") {
      appliedSnapshots.withLock { $0 == 1 }
    }

    currentRequest.withLock { $0 = Self.makeRequest(marker: "stale") }
    controller.refresh()
    currentRequest.withLock { $0 = Self.makeRequest(marker: "latest") }
    controller.refresh()

    try await waitUntil("latest snapshot before stale rejection") {
      appliedSnapshots.withLock { $0 == 2 }
    }
    releaseStaleResponse.signal()

    try await waitUntil(
      "reconnect after stale rejection",
      timeoutNanoseconds: 4_000_000_000
    ) {
      requestCount.withLock { $0 >= 4 } && appliedSnapshots.withLock { $0 >= 3 }
    }
  }

  private static func makeRequest(marker: String) -> CalendarAgentRequest {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    return .subscribe(
      CalendarAgentQuery(
        startDate: start,
        endDate: start.addingTimeInterval(86_400),
        showBirthdays: false,
        emptyText: marker,
        birthdaysTitle: "Birthdays",
        birthdaysDateFormat: "dd.MM.yyyy",
        birthdaysShowAge: false
      )
    )
  }

  nonisolated private static func makeSnapshot() -> CalendarAgentSnapshot {
    CalendarAgentSnapshot(
      accessGranted: true,
      permissionState: "authorized",
      generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
      writableCalendars: [],
      events: [],
      sections: []
    )
  }

  private func waitUntil(
    _ description: String,
    timeoutNanoseconds: UInt64 = 1_000_000_000,
    condition: @escaping @MainActor () -> Bool
  ) async throws {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds

    while DispatchTime.now().uptimeNanoseconds < deadline {
      if condition() { return }
      try await Task.sleep(nanoseconds: 10_000_000)
    }

    XCTFail("Timed out waiting for \(description)")
  }
}
