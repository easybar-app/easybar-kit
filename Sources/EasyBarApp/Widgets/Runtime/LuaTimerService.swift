import EasyBarShared
import Foundation

/// Owns host-side one-shot timers requested by the Lua runtime.
actor LuaTimerService {
  /// Hard limit for one runtime session's active one-shot timers.
  static let maximumActiveTimers = 1_024

  private struct ActiveTimer {
    let runtimeSessionID: UInt64
    let task: Task<Void, Never>
  }

  private struct LuaTimerResponse: Encodable {
    let protocolVersion = easyBarLuaRuntimeProtocolVersion
    let type = "timer_fired"
    let token: String

    enum CodingKeys: String, CodingKey {
      case protocolVersion = "protocol_version"
      case type
      case token
    }
  }

  private struct LuaTimerRejectedResponse: Encodable {
    let protocolVersion = easyBarLuaRuntimeProtocolVersion
    let type = "timer_rejected"
    let token: String
    let message: String

    enum CodingKeys: String, CodingKey {
      case protocolVersion = "protocol_version"
      case type
      case token
      case message
    }
  }

  private let logger: ProcessLogger
  private let maximumActiveTimers: Int
  private let sendResponse: @Sendable (String) async -> Void
  private let encoder = JSONEncoder()
  private var activeTimers: [String: ActiveTimer] = [:]
  private var activeRuntimeSessionID: UInt64?

  init(logger: ProcessLogger, luaRuntime: LuaRuntime) {
    self.logger = logger
    self.maximumActiveTimers = Self.maximumActiveTimers
    self.sendResponse = { encoded in
      await luaRuntime.send(encoded)
    }
  }

  /// Creates one timer service with injected limits and output for focused tests.
  init(
    logger: ProcessLogger,
    maximumActiveTimers: Int,
    sendResponse: @escaping @Sendable (String) async -> Void
  ) {
    self.logger = logger
    self.maximumActiveTimers = max(1, maximumActiveTimers)
    self.sendResponse = sendResponse
  }

  /// Cancels and forgets every timer owned by the current Lua runtime session.
  func reset() {
    let tasks = activeTimers.values.map(\.task)
    activeTimers.removeAll()
    activeRuntimeSessionID = nil
    for task in tasks {
      task.cancel()
    }
  }

  /// Schedules one non-blocking one-shot timer for the active runtime session.
  func schedule(
    token: String,
    delaySeconds: TimeInterval,
    runtimeSessionID: UInt64,
    isRuntimeSessionActive: @escaping @Sendable (UInt64) async -> Bool
  ) async {
    if activeRuntimeSessionID != runtimeSessionID {
      reset()
      activeRuntimeSessionID = runtimeSessionID
    }

    if activeTimers[token] == nil, activeTimers.count >= maximumActiveTimers {
      logger.warn(
        "lua timer rejected because limit was reached",
        .field("token", token),
        .field("active_timers", activeTimers.count),
        .field("max_timers", maximumActiveTimers)
      )
      await sendTimerRejected(
        token: token,
        message: "maximum active timer limit reached"
      )
      return
    }

    activeTimers[token]?.task.cancel()
    let nanoseconds = clampedSleepNanoseconds(from: delaySeconds)
    let task = Task { [weak self] in
      do {
        try await Task.sleep(for: .nanoseconds(Int64(clamping: nanoseconds)))
      } catch {
        return
      }
      await self?.fire(
        token: token,
        runtimeSessionID: runtimeSessionID,
        isRuntimeSessionActive: isRuntimeSessionActive
      )
    }
    activeTimers[token] = ActiveTimer(runtimeSessionID: runtimeSessionID, task: task)

    logger.debug(
      "lua timer scheduled",
      .field("token", token),
      .field("delay_seconds", delaySeconds)
    )
  }

  /// Cancels one pending timer owned by the active runtime session.
  func cancel(token: String, runtimeSessionID: UInt64) {
    guard activeRuntimeSessionID == runtimeSessionID,
      let timer = activeTimers.removeValue(forKey: token),
      timer.runtimeSessionID == runtimeSessionID
    else {
      return
    }
    timer.task.cancel()
    logger.debug("lua timer cancelled", .field("token", token))
  }

  /// Sends one deterministic rejection so Lua can release its pending callback.
  private func sendTimerRejected(token: String, message: String) async {
    let response = LuaTimerRejectedResponse(token: token, message: message)
    guard
      let data = try? encoder.encode(response),
      let encoded = String(data: data, encoding: .utf8)
    else {
      logger.error("failed to encode lua timer rejection", .field("token", token))
      return
    }

    await sendResponse(encoded)
  }

  private func fire(
    token: String,
    runtimeSessionID: UInt64,
    isRuntimeSessionActive: @escaping @Sendable (UInt64) async -> Bool
  ) async {
    guard activeRuntimeSessionID == runtimeSessionID,
      let timer = activeTimers.removeValue(forKey: token),
      timer.runtimeSessionID == runtimeSessionID,
      await isRuntimeSessionActive(runtimeSessionID)
    else {
      return
    }

    let response = LuaTimerResponse(token: token)
    guard
      let data = try? encoder.encode(response),
      let encoded = String(data: data, encoding: .utf8)
    else {
      logger.error("failed to encode lua timer response", .field("token", token))
      return
    }

    await sendResponse(encoded)
  }
}
