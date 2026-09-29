/// Stores AeroSpace refresh token data.
struct AeroSpaceRefreshToken: Equatable, Sendable {
  /// The generation for this AeroSpace refresh token.
  let generation: UInt64
  /// The stable identifier for this AeroSpace refresh token.
  let requestID: UInt64
  /// The focused state revision for this AeroSpace refresh token.
  let focusedStateRevision: UInt64
}

/// Stores AeroSpace focused state token data.
struct AeroSpaceFocusedStateToken: Equatable, Sendable {
  /// The generation for this AeroSpace focused state token.
  let generation: UInt64
  /// The stable identifier for this AeroSpace focused state token.
  let requestID: UInt64
}

/// Stores AeroSpace workspace focus token data.
struct AeroSpaceWorkspaceFocusToken: Equatable, Sendable {
  /// The generation for this AeroSpace workspace focus token.
  let generation: UInt64
  /// The stable identifier for this AeroSpace workspace focus token.
  let requestID: UInt64
}

/// Stores AeroSpace refresh sequence data.
struct AeroSpaceRefreshSequence: Sendable {
  /// The stable identifier for this AeroSpace refresh sequence.
  private var latestRequestID: UInt64 = 0

  /// Returns the issue.
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

  /// Returns whether this state is current.
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
