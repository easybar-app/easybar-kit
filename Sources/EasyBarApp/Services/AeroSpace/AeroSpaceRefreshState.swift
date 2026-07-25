struct AeroSpaceRefreshToken: Equatable, Sendable {
  let generation: UInt64
  let requestID: UInt64
  let focusedStateRevision: UInt64
}

struct AeroSpaceFocusedStateToken: Equatable, Sendable {
  let generation: UInt64
  let requestID: UInt64
}

struct AeroSpaceWorkspaceFocusToken: Equatable, Sendable {
  let generation: UInt64
  let requestID: UInt64
}

struct AeroSpaceRefreshSequence: Sendable {
  private var latestRequestID: UInt64 = 0

  mutating func issue(
    generation: UInt64,
    focusedStateRevision: UInt64 = 0
  ) -> AeroSpaceRefreshToken {
    latestRequestID &+= 1
    return AeroSpaceRefreshToken(
      generation: generation,
      requestID: latestRequestID,
      focusedStateRevision: focusedStateRevision
    )
  }

  func isCurrent(_ token: AeroSpaceRefreshToken, generation: UInt64) -> Bool {
    token.generation == generation && token.requestID == latestRequestID
  }
}

/// Health of the most recent AeroSpace snapshot attempt.
enum AeroSpaceSnapshotStatus: Equatable, Sendable {
  /// No complete snapshot has been loaded yet.
  case unavailable(message: String)
  /// The published state came from the latest successful refresh.
  case current
  /// Published state is last-known-good because the latest refresh failed.
  case stale(message: String)
}
