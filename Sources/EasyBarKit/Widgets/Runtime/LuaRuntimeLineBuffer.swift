import Foundation

/// Bounded handoff from the Lua socket callback into the actor-owned widget engine.
final class LuaRuntimeLineBuffer: @unchecked Sendable {
  /// Result of attempting to enqueue one complete runtime protocol line.
  enum EnqueueResult: Equatable {
    case enqueued
    case overflow
    case terminated
  }

  let stream: AsyncStream<String>
  private let continuation: AsyncStream<String>.Continuation

  init(maximumBufferedLines: Int) {
    let (stream, continuation) = AsyncStream<String>.makeStream(
      bufferingPolicy: .bufferingOldest(max(1, maximumBufferedLines))
    )
    self.stream = stream
    self.continuation = continuation
  }

  /// Enqueues one line without silently discarding a full-buffer message.
  func enqueue(_ line: String) -> EnqueueResult {
    switch continuation.yield(line) {
    case .enqueued:
      return .enqueued
    case .dropped:
      return .overflow
    case .terminated:
      return .terminated
    @unknown default:
      return .overflow
    }
  }

  /// Finishes the stream and wakes its consumer.
  func finish() {
    continuation.finish()
  }
}
