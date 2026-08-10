import EasyBarShared
import Foundation

/// One-shot calendar-agent client used by the event composer for fresh writable-calendar options.
@MainActor
final class ComposerCalendarAgentClient {
  /// Logger used for composer-calendar agent diagnostics.
  private let logger: ProcessLogger
  /// Active calendar-agent config snapshot.
  private var calendarAgentConfig: ConfigSnapshot.CalendarAgent
  private let store: NativeComposerCalendarStore
  /// Monotonic refresh generation used to ignore stale one-shot responses.
  private var refreshGeneration: UInt64 = 0

  /// Creates one composer-calendar agent client.
  init(
    logger: ProcessLogger,
    calendarAgentConfig: ConfigSnapshot.CalendarAgent,
    store: NativeComposerCalendarStore
  ) {
    self.logger = logger
    self.calendarAgentConfig = calendarAgentConfig
    self.store = store
  }

  /// Replaces the active calendar-agent config snapshot.
  func updateConfiguration(_ calendarAgentConfig: ConfigSnapshot.CalendarAgent) {
    self.calendarAgentConfig = calendarAgentConfig

    guard calendarAgentConfig.enabled else {
      refreshGeneration &+= 1
      store.clear()
      return
    }

    if store.snapshot != nil {
      refresh()
    }
  }

  /// Requests one fresh composer snapshot from the calendar agent.
  func refresh() {
    guard calendarAgentConfig.enabled else {
      refreshGeneration &+= 1
      store.clear()
      return
    }

    refreshGeneration &+= 1
    let generation = refreshGeneration
    let socketPath = calendarAgentConfig.socketPath
    let request = makeRequest(referenceDate: Date())

    logger.debug(
      "requesting composer calendar snapshot",
      .field("socket", socketPath)
    )

    DetachedTask.run(priority: .userInitiated) { [weak self] in
      do {
        let response = try CalendarAgentOneShotClient.send(
          request: request,
          socketPath: socketPath
        )

        await MainActor.run { [weak self] in
          self?.handleRefreshResponse(
            response,
            generation: generation,
            socketPath: socketPath
          )
        }
      } catch {
        await MainActor.run { [weak self] in
          self?.handleRefreshError(
            error,
            generation: generation,
            socketPath: socketPath
          )
        }
      }
    }
  }

  /// Handles one composer-calendar snapshot response.
  private func handleRefreshResponse(
    _ response: CalendarAgentMessage,
    generation: UInt64,
    socketPath: String
  ) {
    guard isCurrentResponse(generation: generation, socketPath: socketPath) else { return }

    switch response.kind {
    case .snapshot:
      guard let snapshot = response.snapshot else {
        logger.warn("composer calendar snapshot response had no payload")
        store.clear()
        return
      }

      store.apply(snapshot: snapshot)

    case .error:
      logger.warn(
        "composer calendar snapshot request failed",
        .field("message", response.message ?? "unknown")
      )
      store.clear()

    default:
      logger.warn(
        "composer calendar snapshot request returned unexpected response",
        .field("response", response.kind.rawValue)
      )
      store.clear()
    }
  }

  /// Handles one composer-calendar one-shot request failure.
  private func handleRefreshError(
    _ error: Error,
    generation: UInt64,
    socketPath: String
  ) {
    guard isCurrentResponse(generation: generation, socketPath: socketPath) else { return }

    logger.warn(
      "composer calendar snapshot request failed",
      .field("error", error)
    )
    store.clear()
  }

  /// Returns whether a one-shot response still belongs to the current config and refresh generation.
  private func isCurrentResponse(generation: UInt64, socketPath: String) -> Bool {
    generation == refreshGeneration && socketPath == calendarAgentConfig.socketPath
  }

  /// Builds a minimal fetch request whose payload includes fresh writable-calendar metadata.
  private func makeRequest(referenceDate: Date) -> CalendarAgentRequest {
    let calendar = Calendar.current
    let start = calendar.startOfDay(for: referenceDate)
    let end =
      calendar.date(byAdding: .day, value: 1, to: start)
      ?? referenceDate.addingTimeInterval(86_400)

    return CalendarAgentRequest(
      command: .fetch,
      query: CalendarAgentQuery(
        startDate: start,
        endDate: end,
        showBirthdays: false,
        emptyText: "",
        birthdaysTitle: "",
        birthdaysDateFormat: "dd.MM.yyyy",
        birthdaysShowAge: false
      )
    )
  }
}
