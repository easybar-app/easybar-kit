import Foundation

/// One event emitted by `aerospace subscribe`.
struct AeroSpaceSubscriptionEvent: Decodable, Equatable, Sendable {
  enum RefreshPolicy: Equatable, Sendable {
    case fastFocusAndDebouncedSnapshot
    case fastWorkspaceAndImmediateSnapshot
    case immediateSnapshot
    case debouncedSnapshot
  }

  /// AeroSpace event names that affect EasyBar's AeroSpace-backed state.
  enum Name {
    static let focusChanged = "focus-changed"
    static let focusedWorkspaceChanged = "focused-workspace-changed"
    static let focusedMonitorChanged = "focused-monitor-changed"
    static let modeChanged = "mode-changed"
    static let windowDetected = "window-detected"
    static let bindingTriggered = "binding-triggered"
    static let unknown = "unknown"
  }

  /// Arguments for the long-lived AeroSpace event stream.
  ///
  /// `--all` keeps EasyBar aligned with AeroSpace's current event set, and the
  /// default initial send gives the app one immediate sync signal on connect.
  static let subscribeArguments = ["subscribe", "--all"]

  /// Human-readable subscription scope used in logs.
  static let subscriptionDescription = "all"

  /// Trailing delay used to coalesce focus and other high-frequency event bursts.
  static let fullSnapshotDebounceNanoseconds: UInt64 = 120_000_000

  /// Raw AeroSpace event name.
  let name: String
  /// Focused workspace supplied by workspace-change events, when available.
  let workspace: String?

  /// Creates one event with a raw AeroSpace event name.
  init(name: String, workspace: String? = nil) {
    self.name = name
    self.workspace = workspace
  }

  /// Decodes one JSON-line event from AeroSpace.
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    name = try container.decode(String.self, forKey: .name)
    workspace = try container.decodeIfPresent(String.self, forKey: .workspace)
  }

  /// Refresh behavior appropriate for this event's ordering and frequency.
  var refreshPolicy: RefreshPolicy {
    switch name {
    case Name.focusChanged:
      return .fastFocusAndDebouncedSnapshot
    case Name.focusedWorkspaceChanged:
      return .fastWorkspaceAndImmediateSnapshot
    case Name.focusedMonitorChanged:
      return .immediateSnapshot
    default:
      return .debouncedSnapshot
    }
  }

  /// Matching EasyBar app event for Lua subscriptions, when available.
  var appEvent: AppEvent? {
    switch name {
    case Name.focusChanged:
      return .focusChange
    case Name.focusedWorkspaceChanged, Name.focusedMonitorChanged:
      return .workspaceChange
    default:
      return nil
    }
  }

  private enum CodingKeys: String, CodingKey {
    case name = "_event"
    case workspace
  }
}
