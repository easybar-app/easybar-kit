import EasyBarShared
import Foundation

/// One resolved snapshot of AeroSpace state.
struct AeroSpaceSnapshot: Equatable, Sendable {
  /// Workspace items to publish.
  let spaces: [SpaceItem]
  /// Focused application when known.
  let focusedApp: SpaceApp?
  /// Focused window layout mode.
  let focusedLayoutMode: AeroSpaceLayoutMode
}

/// Focus-sensitive subset that can be loaded without rebuilding every workspace.
struct AeroSpaceFocusedState: Equatable, Sendable {
  let app: SpaceApp?
  let layoutMode: AeroSpaceLayoutMode
}

/// Loads and parses AeroSpace CLI JSON output into app-ready state.
enum AeroSpaceSnapshotLoader {
  /// Reads the current AeroSpace snapshot with an asynchronous command runner.
  static func load(
    run: @escaping @Sendable ([String]) async -> String?,
    resolveAppID: @Sendable (String, String?) -> String
  ) async throws -> AeroSpaceSnapshot {
    let state = try await AsyncJSONAeroSpaceSnapshotProvider(run: run).loadState()
    try Task.checkCancellation()
    return buildSnapshot(state: state, resolveAppID: resolveAppID)
  }

  /// Reads only the focused window state for latency-sensitive focus updates.
  static func loadFocusedState(
    run: @escaping @Sendable ([String]) async -> String?,
    resolveAppID: @Sendable (String, String?) -> String
  ) async throws -> AeroSpaceFocusedState {
    let output = try requireOutput(
      await run(AeroSpaceSnapshotCommands.focusedWindow),
      command: AeroSpaceSnapshotCommands.focusedWindowDescription
    )
    try Task.checkCancellation()
    let focusedWindow = try JSONAeroSpaceSnapshotParser.parseFocusedWindow(output)
    return AeroSpaceFocusedState(
      app: makeFocusedApp(focusedWindow, resolveAppID: resolveAppID),
      layoutMode: parseLayoutMode(focusedWindow?.layout ?? "")
    )
  }

  /// Reads the current AeroSpace snapshot with a synchronous test or utility runner.
  static func loadSynchronously(
    run: @escaping ([String]) -> String?,
    resolveAppID: (String, String?) -> String
  ) throws -> AeroSpaceSnapshot {
    try buildSnapshot(
      state: JSONAeroSpaceSnapshotProvider(run: run).loadState(),
      resolveAppID: resolveAppID
    )
  }

  /// Builds app-facing state from provider-neutral AeroSpace state.
  private static func buildSnapshot(
    state: AeroSpaceRawSnapshot,
    resolveAppID: (String, String?) -> String
  ) -> AeroSpaceSnapshot {
    let groupedApps = Dictionary(grouping: state.windows, by: \.workspace)

    let spaces =
      state.workspaces
      .map { workspace in
        SpaceItem(
          id: workspace.name,
          name: workspace.name,
          isFocused: workspace.isFocused,
          isVisible: workspace.isVisible,
          apps: deduplicateApps(groupedApps[workspace.name] ?? [], resolveAppID: resolveAppID)
        )
      }

    return AeroSpaceSnapshot(
      spaces: spaces,
      focusedApp: makeFocusedApp(state.focusedWindow, resolveAppID: resolveAppID),
      focusedLayoutMode: parseLayoutMode(state.focusedLayout)
    )
  }

  /// Deduplicates apps per workspace.
  private static func deduplicateApps(
    _ windows: [WindowDTO],
    resolveAppID: (String, String?) -> String
  ) -> [SpaceApp] {
    var seen = Set<String>()
    var result: [SpaceApp] = []

    for window in windows {
      let key = resolveAppID(
        window.name,
        window.bundlePath.isEmpty ? nil : window.bundlePath
      )
      guard !seen.contains(key) else { continue }

      seen.insert(key)
      result.append(
        makeSpaceApp(name: window.name, bundlePath: window.bundlePath, resolveAppID: resolveAppID))
    }

    return result
  }

  /// Builds the focused app from parsed AeroSpace window data.
  private static func makeFocusedApp(
    _ window: FocusedWindowDTO?,
    resolveAppID: (String, String?) -> String
  ) -> SpaceApp? {
    guard let window else { return nil }

    let bundlePath = window.bundlePath.isEmpty ? nil : window.bundlePath
    let id = resolveAppID(window.name, bundlePath)

    guard !id.isEmpty else { return nil }

    return SpaceApp(
      id: id,
      bundleID: "",
      name: window.name,
      bundlePath: bundlePath
    )
  }

  /// Parses one focused layout mode from AeroSpace output.
  private static func parseLayoutMode(_ output: String) -> AeroSpaceLayoutMode {
    let normalized = output.trimmingCharacters(in: .whitespacesAndNewlines)

    switch normalized {
    case AeroSpaceLayoutMode.hTiles.rawValue:
      return .hTiles
    case AeroSpaceLayoutMode.vTiles.rawValue:
      return .vTiles
    case AeroSpaceLayoutMode.hAccordion.rawValue:
      return .hAccordion
    case AeroSpaceLayoutMode.vAccordion.rawValue:
      return .vAccordion
    case AeroSpaceLayoutMode.floating.rawValue:
      return .floating
    default:
      return .unknown
    }
  }

  /// Builds one `SpaceApp` from parsed AeroSpace window data.
  private static func makeSpaceApp(
    name: String,
    bundlePath: String,
    resolveAppID: (String, String?) -> String
  ) -> SpaceApp {
    let normalizedBundlePath = bundlePath.isEmpty ? nil : bundlePath

    return SpaceApp(
      id: resolveAppID(name, normalizedBundlePath),
      bundleID: "",
      name: name,
      bundlePath: normalizedBundlePath
    )
  }
}

/// Loads AeroSpace state from formatted JSON CLI output.
private struct JSONAeroSpaceSnapshotProvider {
  let run: ([String]) -> String?

  func loadState() throws -> AeroSpaceRawSnapshot {
    let workspacesOutput = try requireOutput(
      run(AeroSpaceSnapshotCommands.workspaces),
      command: AeroSpaceSnapshotCommands.workspacesDescription
    )
    let windowsOutput = try requireOutput(
      run(AeroSpaceSnapshotCommands.windows),
      command: AeroSpaceSnapshotCommands.windowsDescription
    )
    let focusedWindowOutput = try requireOutput(
      run(AeroSpaceSnapshotCommands.focusedWindow),
      command: AeroSpaceSnapshotCommands.focusedWindowDescription
    )

    return try JSONAeroSpaceSnapshotParser.parse(
      workspacesOutput: workspacesOutput,
      windowsOutput: windowsOutput,
      focusedWindowOutput: focusedWindowOutput
    )
  }
}

/// Loads AeroSpace state without blocking the caller's cooperative executor.
private struct AsyncJSONAeroSpaceSnapshotProvider {
  let run: @Sendable ([String]) async -> String?

  func loadState() async throws -> AeroSpaceRawSnapshot {
    let workspacesOutput = try requireOutput(
      await run(AeroSpaceSnapshotCommands.workspaces),
      command: AeroSpaceSnapshotCommands.workspacesDescription
    )
    try Task.checkCancellation()

    let windowsOutput = try requireOutput(
      await run(AeroSpaceSnapshotCommands.windows),
      command: AeroSpaceSnapshotCommands.windowsDescription
    )
    try Task.checkCancellation()

    let focusedWindowOutput = try requireOutput(
      await run(AeroSpaceSnapshotCommands.focusedWindow),
      command: AeroSpaceSnapshotCommands.focusedWindowDescription
    )
    try Task.checkCancellation()

    return try JSONAeroSpaceSnapshotParser.parse(
      workspacesOutput: workspacesOutput,
      windowsOutput: windowsOutput,
      focusedWindowOutput: focusedWindowOutput
    )
  }
}

/// Canonical formatted JSON commands used for every snapshot.
private enum AeroSpaceSnapshotCommands {
  static let workspaces = [
    "list-workspaces",
    "--all",
    "--json",
    "--format",
    "%{workspace} %{workspace-is-focused} %{workspace-is-visible}",
  ]
  static let windows = [
    "list-windows",
    "--all",
    "--json",
    "--format",
    "%{workspace} %{app-name} %{app-bundle-path}",
  ]
  static let focusedWindow = [
    "list-windows",
    "--focused",
    "--json",
    "--format",
    "%{workspace} %{app-name} %{app-bundle-path} %{window-layout}",
  ]

  static let workspacesDescription = "list-workspaces --all --json --format"
  static let windowsDescription = "list-windows --all --json --format"
  static let focusedWindowDescription = "list-windows --focused --json --format"
}

/// Decodes the three formatted JSON payloads into provider-neutral state.
private enum JSONAeroSpaceSnapshotParser {
  static func parse(
    workspacesOutput: String,
    windowsOutput: String,
    focusedWindowOutput: String
  ) throws -> AeroSpaceRawSnapshot {
    let decoder = JSONDecoder()
    let workspaces = try decode([JSONWorkspaceDTO].self, from: workspacesOutput, decoder: decoder)
      .map {
        WorkspaceDTO(
          name: $0.workspace,
          isFocused: $0.workspaceIsFocused,
          isVisible: $0.workspaceIsVisible
        )
      }
    let windows = try decode([JSONWindowDTO].self, from: windowsOutput, decoder: decoder)
      .map {
        WindowDTO(
          workspace: $0.workspace,
          name: $0.appName,
          bundlePath: $0.appBundlePath
        )
      }
    let focusedWindow = try parseFocusedWindow(focusedWindowOutput, decoder: decoder)

    return AeroSpaceRawSnapshot(
      workspaces: workspaces,
      windows: windows,
      focusedWindow: focusedWindow,
      focusedLayout: focusedWindow?.layout ?? ""
    )
  }

  /// Decodes the focused-window command used by both full and fast snapshots.
  static func parseFocusedWindow(_ output: String) throws -> FocusedWindowDTO? {
    try parseFocusedWindow(output, decoder: JSONDecoder())
  }

  private static func parseFocusedWindow(
    _ output: String,
    decoder: JSONDecoder
  ) throws -> FocusedWindowDTO? {
    let focusedWindows = try decode([JSONWindowDTO].self, from: output, decoder: decoder)
    return focusedWindows.first.map {
      FocusedWindowDTO(
        name: $0.appName,
        bundlePath: $0.appBundlePath,
        layout: $0.windowLayout ?? ""
      )
    }
  }

  /// Decodes one JSON payload.
  private static func decode<T: Decodable>(
    _ type: T.Type,
    from output: String,
    decoder: JSONDecoder
  ) throws -> T {
    guard let data = output.data(using: .utf8) else {
      throw AeroSpaceSnapshotProviderError.invalidUTF8
    }

    do {
      return try decoder.decode(type, from: data)
    } catch {
      throw AeroSpaceSnapshotProviderError.decodeFailed(error: error)
    }
  }
}

/// Requires command output from a provider command.
private func requireOutput(_ output: String?, command: String) throws -> String {
  guard let output else {
    throw AeroSpaceSnapshotProviderError.commandFailed(command: command)
  }

  return output
}

/// Minimum supported AeroSpace version for JSON snapshot loading.
struct AeroSpaceVersion: Comparable, CustomStringConvertible, Equatable {
  let major: Int
  let minor: Int
  let patch: Int

  var description: String {
    "\(major).\(minor).\(patch)"
  }

  static func < (lhs: AeroSpaceVersion, rhs: AeroSpaceVersion) -> Bool {
    if lhs.major != rhs.major { return lhs.major < rhs.major }
    if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
    return lhs.patch < rhs.patch
  }

  init(major: Int, minor: Int, patch: Int) {
    self.major = major
    self.minor = minor
    self.patch = patch
  }

  init?(_ text: String) {
    let pattern = #"(\d+)\.(\d+)\.(\d+)"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges == 4 else {
      return nil
    }

    func component(_ index: Int) -> Int? {
      guard let range = Range(match.range(at: index), in: text) else { return nil }
      return Int(text[range])
    }

    guard let major = component(1), let minor = component(2), let patch = component(3) else {
      return nil
    }

    self.major = major
    self.minor = minor
    self.patch = patch
  }
}

/// Validates the AeroSpace version required by EasyBar.
enum AeroSpaceVersionRequirement {
  /// First supported AeroSpace version for EasyBar v0.4.0 and newer.
  static let minimum = AeroSpaceVersion(major: 0, minor: 21, patch: 0)

  /// Validates raw `aerospace --version` output.
  static func validate(output: String) throws {
    let client = namedVersion(in: output, label: "aerospace CLI client version")
    let server = namedVersion(in: output, label: "AeroSpace.app server version")

    guard let client, let server else {
      throw AeroSpaceVersionRequirementError.unparseable(output: output)
    }

    guard client >= minimum else {
      throw AeroSpaceVersionRequirementError.unsupportedClientVersion(
        current: client,
        minimum: minimum
      )
    }

    guard server >= minimum else {
      throw AeroSpaceVersionRequirementError.unsupportedServerVersion(
        current: server,
        minimum: minimum
      )
    }
  }

  /// Validates the installed AeroSpace CLI using a command runner.
  static func validate(run: ([String]) -> String?) throws {
    let output = try requireOutput(run(["--version"]), command: "--version")
    try validate(output: output)
  }

  /// Extracts one named version from `aerospace --version` output.
  private static func namedVersion(in output: String, label: String) -> AeroSpaceVersion? {
    output
      .split(whereSeparator: \.isNewline)
      .lazy
      .filter { $0.contains(label) }
      .compactMap { AeroSpaceVersion(String($0)) }
      .first
  }
}

/// Raw provider-neutral AeroSpace state.
private struct AeroSpaceRawSnapshot {
  let workspaces: [WorkspaceDTO]
  let windows: [WindowDTO]
  let focusedWindow: FocusedWindowDTO?
  let focusedLayout: String
}

/// Raw workspace state parsed from AeroSpace output.
private struct WorkspaceDTO {
  /// Workspace name.
  let name: String
  /// Whether the workspace is focused.
  let isFocused: Bool
  /// Whether the workspace is visible.
  let isVisible: Bool
}

/// Raw window state parsed from AeroSpace output.
private struct WindowDTO {
  /// Workspace containing the window.
  let workspace: String
  /// App name.
  let name: String
  /// App bundle path reported for the window.
  let bundlePath: String
}

/// Raw focused window state parsed from AeroSpace output.
private struct FocusedWindowDTO {
  /// App name.
  let name: String
  /// App bundle path reported for the window.
  let bundlePath: String
  /// Layout of the focused window container.
  let layout: String
}

/// JSON workspace shape returned by `aerospace list-workspaces --json --format`.
private struct JSONWorkspaceDTO: Decodable {
  let workspace: String
  let workspaceIsFocused: Bool
  let workspaceIsVisible: Bool

  enum CodingKeys: String, CodingKey {
    case workspace
    case workspaceIsFocused = "workspace-is-focused"
    case workspaceIsVisible = "workspace-is-visible"
  }
}

/// JSON window shape returned by `aerospace list-windows --json --format`.
private struct JSONWindowDTO: Decodable {
  let workspace: String
  let appName: String
  let appBundlePath: String
  let windowLayout: String?

  enum CodingKeys: String, CodingKey {
    case workspace
    case appName = "app-name"
    case appBundlePath = "app-bundle-path"
    case windowLayout = "window-layout"
  }
}

/// Snapshot provider failures used for diagnostics.
private enum AeroSpaceSnapshotProviderError: Error, CustomStringConvertible {
  case commandFailed(command: String)
  case invalidUTF8
  case decodeFailed(error: Error)

  var description: String {
    switch self {
    case .commandFailed(let command):
      return "command failed: \(command)"
    case .invalidUTF8:
      return "invalid UTF-8 output"
    case .decodeFailed(let error):
      return "failed to decode JSON output: \(error)"
    }
  }
}

/// AeroSpace version requirement failures.
enum AeroSpaceVersionRequirementError: Error, CustomStringConvertible {
  case unparseable(output: String)
  case unsupportedClientVersion(current: AeroSpaceVersion, minimum: AeroSpaceVersion)
  case unsupportedServerVersion(current: AeroSpaceVersion, minimum: AeroSpaceVersion)

  var description: String {
    switch self {
    case .unparseable:
      return "failed to parse AeroSpace client/server versions"
    case .unsupportedClientVersion(let current, let minimum):
      return "unsupported AeroSpace CLI client version \(current); require >= \(minimum)"
    case .unsupportedServerVersion(let current, let minimum):
      return "unsupported AeroSpace.app server version \(current); require >= \(minimum)"
    }
  }
}
