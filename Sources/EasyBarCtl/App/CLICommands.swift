import Darwin
import EasyBarShared
import Foundation

/// Sends one IPC command.
func sendCommand(_ command: IPC.Command, to socketPath: String, context: AppContext) throws {
  context.debug("sending command '\(command.rawValue)' to \(socketPath)")

  let response = try sendIPCRequest(
    .makeCommand(command),
    to: socketPath,
    context: context
  )

  try expectAccepted(response, fallback: "command rejected")
  context.debug("command sent")
}

/// Runs one native inbox command through the app control socket.
func runInboxCommand(
  _ command: InboxCLICommand,
  socketPath: String,
  context: AppContext
) throws {
  let request: IPC.InboxRequest
  let printsItems: Bool
  let json: Bool

  switch command {
  case .send(let item):
    request = .init(operation: .send, item: item)
    printsItems = false
    json = false
  case .list(let source, let unreadOnly, let useJSON):
    request = .init(operation: .read, source: source, unreadOnly: unreadOnly)
    printsItems = true
    json = useJSON
  case .markRead(let source, let id):
    request = .init(operation: .markRead, source: source, id: id)
    printsItems = false
    json = false
  case .markUnread(let source, let id):
    request = .init(operation: .markUnread, source: source, id: id)
    printsItems = false
    json = false
  case .dismiss(let source, let id):
    request = .init(operation: .dismiss, source: source, id: id)
    printsItems = false
    json = false
  case .remove(let source, let id):
    request = .init(operation: .remove, source: source, id: id)
    printsItems = false
    json = false
  case .clear(let source):
    request = .init(operation: .clear, source: source)
    printsItems = false
    json = false
  }

  let response = try sendIPCRequest(.makeInbox(request), to: socketPath, context: context)
  if printsItems {
    let items = try expectInbox(response, fallback: "inbox list failed")
    try CLIOutput.printInboxItems(items, json: json)
  } else {
    try expectAccepted(response, fallback: "inbox command rejected")
  }
}

func restartCalendarAgent(socketPath: String?, context: AppContext) throws {
  let resolution = try resolveCalendarAgentSocket(explicitPath: socketPath)
  logSocketResolution(resolution, kind: "calendar agent", context: context)
  let path = resolution.path
  context.debug("requesting calendar agent restart through \(path)")
  do {
    try AgentRestartClient.restartCalendarAgent(socketPath: path)
  } catch {
    throw AppError.message("calendar agent restart failed: \(error.localizedDescription)")
  }
}

func restartNetworkAgent(socketPath: String?, context: AppContext) throws {
  let resolution = try resolveNetworkAgentSocket(explicitPath: socketPath)
  logSocketResolution(resolution, kind: "network agent", context: context)
  let path = resolution.path
  context.debug("requesting network agent restart through \(path)")
  do {
    try AgentRestartClient.restartNetworkAgent(socketPath: path)
  } catch {
    throw AppError.message("network agent restart failed: \(error.localizedDescription)")
  }
}

func restartAgents(context: AppContext) throws {
  let paths = try resolveAgentSockets()
  logSocketResolution(paths.calendar, kind: "calendar agent", context: context)
  logSocketResolution(paths.network, kind: "network agent", context: context)
  var failures: [String] = []

  do {
    try AgentRestartClient.restartCalendarAgent(socketPath: paths.calendar.path)
  } catch {
    failures.append("calendar: \(error.localizedDescription)")
  }

  do {
    try AgentRestartClient.restartNetworkAgent(socketPath: paths.network.path)
  } catch {
    failures.append("network: \(error.localizedDescription)")
  }

  guard failures.isEmpty else {
    throw AppError.message("agent restart partially failed (\(failures.joined(separator: "; ")))")
  }
  context.debug("both agent restart requests were acknowledged")
}

/// Queries and prints versions from one or both running helper agents.
func showAgentVersions(
  target: AgentTarget,
  json: Bool,
  socketPath: String?,
  context: AppContext
) throws {
  var entries: [AgentVersionOutputEntry] = []
  var hadFailure = false

  if target == .all {
    entries.append(
      AgentVersionOutputEntry(
        key: "easybar",
        label: "EasyBar",
        status: AgentVersionStatus(
          version: BuildInfo.appVersion,
          protocolVersion: easyBarIPCProtocolVersion,
          matchesEasyBar: true,
          error: nil
        )
      )
    )
  }

  let targets: [AgentTarget] = target == .all ? [.calendar, .network] : [target]
  let resolutions: SharedAgentSocketResolutions?
  if target == .all {
    resolutions = try resolveAgentSockets()
  } else {
    resolutions = nil
  }

  for agent in targets {
    do {
      let entry: AgentVersionOutputEntry
      switch agent {
      case .calendar:
        let resolution =
          try resolutions?.calendar
          ?? resolveCalendarAgentSocket(explicitPath: socketPath)
        logSocketResolution(resolution, kind: "calendar agent", context: context)
        let version = try AgentVersionClient.calendarAgentVersion(socketPath: resolution.path)
        entry = agentVersionEntry(
          key: "calendar",
          label: "Calendar agent",
          version: version.appVersion,
          protocolVersion: version.protocolVersion
        )

      case .network:
        let resolution =
          try resolutions?.network
          ?? resolveNetworkAgentSocket(explicitPath: socketPath)
        logSocketResolution(resolution, kind: "network agent", context: context)
        let version = try AgentVersionClient.networkAgentVersion(socketPath: resolution.path)
        entry = agentVersionEntry(
          key: "network",
          label: "Network agent",
          version: version.appVersion,
          protocolVersion: version.protocolVersion
        )

      case .all:
        continue
      }

      entries.append(entry)
    } catch {
      let label = agent == .calendar ? "Calendar agent" : "Network agent"
      let message = error.localizedDescription
      entries.append(
        AgentVersionOutputEntry(
          key: agent.rawValue,
          label: label,
          status: AgentVersionStatus(
            version: nil,
            protocolVersion: nil,
            matchesEasyBar: false,
            error: message
          )
        )
      )
      hadFailure = true
    }
  }

  try CLIOutput.printAgentVersions(entries, json: json)
  guard !hadFailure else {
    throw AppError.reportedFailure
  }
}

private func agentVersionEntry(
  key: String,
  label: String,
  version: String,
  protocolVersion: String
) -> AgentVersionOutputEntry {
  AgentVersionOutputEntry(
    key: key,
    label: label,
    status: AgentVersionStatus(
      version: version,
      protocolVersion: protocolVersion,
      matchesEasyBar: version == BuildInfo.appVersion
        && protocolVersion == easyBarIPCProtocolVersion,
      error: nil
    )
  )
}

private func resolveCalendarAgentSocket(
  explicitPath: String?
) throws -> SharedRuntimeSocketResolution {
  do {
    return try SharedRuntimeSocketResolver.calendarAgentSocket(explicitPath: explicitPath)
  } catch {
    throw AppError.message(
      "failed to resolve calendar agent socket from shared runtime config: "
        + "\(error.localizedDescription). Use --socket PATH to bypass config resolution."
    )
  }
}

private func resolveNetworkAgentSocket(
  explicitPath: String?
) throws -> SharedRuntimeSocketResolution {
  do {
    return try SharedRuntimeSocketResolver.networkAgentSocket(explicitPath: explicitPath)
  } catch {
    throw AppError.message(
      "failed to resolve network agent socket from shared runtime config: "
        + "\(error.localizedDescription). Use --socket PATH to bypass config resolution."
    )
  }
}

private func resolveAgentSockets() throws -> SharedAgentSocketResolutions {
  do {
    return try SharedRuntimeSocketResolver.agentSockets()
  } catch {
    throw AppError.message(
      "failed to resolve agent sockets from shared runtime config: "
        + "\(error.localizedDescription). Fix the config before targeting all agents."
    )
  }
}

/// Fetches one metrics snapshot.
func fetchMetricsSnapshot(from socketPath: String, context: AppContext) throws
  -> IPC.MetricsSnapshot
{
  context.debug("requesting metrics snapshot from \(socketPath)")

  let response = try sendIPCRequest(.makeMetrics(), to: socketPath, context: context)
  return try expectMetrics(response, fallback: "metrics unavailable")
}

/// Streams live metrics.
func streamMetrics(to socketPath: String, context: AppContext) throws {
  let client = MetricsStreamClient(socketPath: socketPath)
  var history = MetricsHistory(limit: 32)
  let terminal = WatchTerminal()
  terminal.activate()
  defer { terminal.restore() }

  try client.stream(request: .makeMetrics(watch: true)) { message in
    guard let snapshot = try metricsSnapshot(fromStreamMessage: message) else { return }

    history.append(snapshot)
    fputs(
      terminal.redrawPrefix
        + MetricsRenderer.watchText(snapshot, history: history, terminalWidth: terminal.width),
      stdout
    )
    fflush(stdout)
  }

  context.debug("metrics stream ended")
}

/// Asks the running EasyBar app to validate config through the control socket.
func validateConfig(configPath: String?, socketPath: String, context: AppContext) throws {
  let requestedConfigPath = explicitValidationConfigPath(configPath)

  if let requestedConfigPath {
    context.debug("requesting config validation for \(requestedConfigPath) through \(socketPath)")
  } else {
    context.debug("requesting default config validation through \(socketPath)")
  }

  let response = try sendIPCRequest(
    .makeValidateConfig(configPath: requestedConfigPath),
    to: socketPath,
    context: context
  )

  let validation = try expectConfigValidated(response, fallback: "config validation failed")
  fputs("config valid: \(validation.path)\n", stdout)
  for warning in validation.warnings {
    fputs("warning: \(warning)\n", stdout)
  }
}

/// Returns the explicit validation path from CLI or environment overrides.
private func explicitValidationConfigPath(_ configPath: String?) -> String? {
  if let configPath, !configPath.isEmpty {
    return configPath
  }

  let environmentPath = ProcessInfo.processInfo.environment[SharedEnvironmentKeys.configPath]
  guard let environmentPath, !environmentPath.isEmpty else {
    return nil
  }

  return environmentPath
}

/// Sends one IPC request and logs the decoded response shape.
private func sendIPCRequest(
  _ request: IPC.Request,
  to socketPath: String,
  context: AppContext
) throws -> IPC.Message {
  let transport = LineSocketClientTransport<IPC.Request, IPC.Message>(socketPath: socketPath)
  let response = try transport.send(request: request)

  context.debug(
    "decoded response kind='\(response.kind.rawValue)' message='\(response.message ?? "<nil>")'"
  )

  return response
}

/// Verifies that one IPC response accepted a fire-and-forget command.
private func expectAccepted(_ response: IPC.Message, fallback: String) throws {
  switch response {
  case .accepted:
    return

  case .rejected:
    throw rejectedResponseError(response, fallback: fallback)

  case .configValidated:
    throw AppError.message("unexpected config validation response")

  case .metrics:
    throw AppError.message("unexpected metrics response")
  case .logSubscribed, .logRecord:
    throw AppError.message("unexpected log stream response")
  case .inbox:
    throw AppError.message("unexpected inbox response")
  }
}

/// Extracts one metrics snapshot from an IPC response.
private func expectMetrics(_ response: IPC.Message, fallback: String) throws -> IPC.MetricsSnapshot {
  switch response {
  case .metrics(let metrics):
    return metrics

  case .rejected:
    throw rejectedResponseError(response, fallback: fallback)

  case .accepted, .configValidated, .logSubscribed, .logRecord, .inbox:
    throw AppError.message(fallback)
  }
}

/// Extracts one config validation result from an IPC response.
private func expectConfigValidated(_ response: IPC.Message, fallback: String) throws
  -> (path: String, warnings: [String])
{
  switch response {
  case .configValidated(let validatedPath, let warnings):
    return (validatedPath, warnings)

  case .rejected:
    throw rejectedResponseError(response, fallback: fallback)

  case .accepted:
    throw AppError.message("config validation did not return a result")

  case .metrics:
    throw AppError.message("unexpected metrics response")
  case .logSubscribed, .logRecord:
    throw AppError.message("unexpected log stream response")
  case .inbox:
    throw AppError.message("unexpected inbox response")
  }
}

/// Returns a snapshot for metrics stream updates and ignores non-data control messages.
private func metricsSnapshot(fromStreamMessage message: IPC.Message) throws -> IPC.MetricsSnapshot? {
  switch message {
  case .metrics(let snapshot):
    return snapshot

  case .rejected:
    throw rejectedResponseError(message, fallback: "metrics rejected")

  case .accepted, .configValidated, .logSubscribed, .logRecord, .inbox:
    return nil
  }
}

/// Extracts inbox items from one control-socket response.
private func expectInbox(_ response: IPC.Message, fallback: String) throws -> [IPC.InboxItem] {
  switch response {
  case .inbox(let items):
    return items
  case .rejected:
    throw rejectedResponseError(response, fallback: fallback)
  case .accepted, .configValidated, .metrics, .logSubscribed, .logRecord:
    throw AppError.message(fallback)
  }
}

/// Builds one AppError from a rejected IPC response and a command-specific fallback.
private func rejectedResponseError(_ response: IPC.Message, fallback: String) -> AppError {
  AppError.message(response.message ?? fallback)
}
