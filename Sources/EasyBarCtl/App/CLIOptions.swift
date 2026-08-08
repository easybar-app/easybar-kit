import EasyBarShared

/// Describes one command-line option accepted by `easybar`.
struct CLIOption: Equatable {
  /// Canonical long-form option, such as `--socket`.
  let flag: String
  /// Optional short-form alias, such as `-s`.
  let short: String?
  /// Human-readable help text.
  let description: String
  /// Optional value placeholder shown after the option.
  let placeholder: String?

  init(
    flag: String,
    short: String? = nil,
    description: String,
    placeholder: String? = nil
  ) {
    self.flag = flag
    self.short = short
    self.description = description
    self.placeholder = placeholder
  }

  /// Canonical option text rendered in help output.
  var helpText: String {
    var text = flag
    if let short {
      text += ", \(short)"
    }
    if let placeholder {
      text += " <\(placeholder)>"
    }
    return text
  }

  /// Long and optional short spellings accepted by the parser.
  var acceptedFlags: [String] {
    [flag] + (short.map { [$0] } ?? [])
  }

  /// Returns whether one argument is this option without an inline value.
  func matches(_ argument: String) -> Bool {
    acceptedFlags.contains(argument)
  }

  /// Returns the value from `--option=value`.
  func inlineValue(from argument: String) -> String? {
    for acceptedFlag in acceptedFlags where acceptedFlag.hasPrefix("--") {
      let prefix = "\(acceptedFlag)="
      if argument.hasPrefix(prefix) {
        return String(argument.dropFirst(prefix.count))
      }
    }
    return nil
  }
}

/// Helper-agent target selected by the CLI.
enum AgentTarget: String, Equatable {
  case calendar
  case network
  case all
}

/// Supported native inbox verbs.
enum InboxCLIVerb: String, Equatable {
  case send
  case list
  case markRead = "mark-read"
  case markUnread = "mark-unread"
  case dismiss
  case remove
  case clear
}

/// Parser behavior associated with one declarative CLI command.
enum CLICommandKind: Equatable {
  case control(IPC.Command)
  case metrics
  case logs
  case validateConfig
  case restartAgent(AgentTarget)
  case versionAgent(AgentTarget)
  case emitEvent
  case inbox(InboxCLIVerb)
  case installWidgetPackage

  /// Whether this command can target one explicit Unix socket.
  var acceptsSocketOverride: Bool {
    switch self {
    case .logs, .restartAgent(.all), .versionAgent(.all), .installWidgetPackage:
      return false
    default:
      return true
    }
  }
}

/// One user-facing command definition.
///
/// This catalog is the source of truth for command paths, descriptions, help,
/// and mapping to the shared IPC command model.
struct CLICommandDescriptor: Equatable {
  let path: [String]
  let description: String
  let kind: CLICommandKind
  let usageArguments: [String]
  let options: [CLIOption]

  init(
    path: [String],
    description: String,
    kind: CLICommandKind,
    usageArguments: [String] = [],
    options: [CLIOption] = []
  ) {
    self.path = path
    self.description = description
    self.kind = kind
    self.usageArguments = usageArguments
    self.options = options
  }

  var commandText: String {
    path.joined(separator: " ")
  }

  var usageText: String {
    (["easybar"] + path + usageArguments).joined(separator: " ")
  }
}

/// One top-level command or command group shown by root help.
struct CLICommandGroup: Equatable {
  let name: String
  let description: String
}

/// Parsed `easybar inbox` operation.
enum InboxCLICommand: Equatable {
  case send(IPC.InboxItem)
  case list(source: String?, unreadOnly: Bool, json: Bool)
  case markRead(source: String, id: String?)
  case markUnread(source: String, id: String?)
  case dismiss(source: String, id: String?)
  case remove(source: String, id: String)
  case clear(source: String?)
}

/// Inputs accepted by `easybar widgets install`.
struct WidgetPackageInstallOptions: Equatable {
  let source: String
  let sha256: String?
  let registry: String?
  let widgetsDirectory: String?
  let useRegistry: Bool
}

/// Supported top-level CLI actions after command-specific options are parsed.
enum CLIAction: Equatable {
  case control(IPC.Command)
  case metrics(watch: Bool)
  case validateConfig(configPath: String?)
  case restartAgent(AgentTarget)
  case versionAgent(AgentTarget, json: Bool)
  case logs(LogCommandOptions)
  case inbox(InboxCLICommand)
  case installWidgetPackage(WidgetPackageInstallOptions)
}

/// Parsed command-line configuration.
struct ParsedArguments: Equatable {
  let action: CLIAction
  let socketPath: String?
  let debugEnabled: Bool
}

/// Defines the declarative command catalog and shared CLI options.
enum CLI {
  static let socketOption = CLIOption(
    flag: "--socket",
    short: "-s",
    description: "Override the relevant Unix socket path",
    placeholder: "path"
  )

  static let debugOption = CLIOption(
    flag: "--debug",
    short: "-d",
    description: "Enable CLI diagnostic output"
  )

  static let versionOption = CLIOption(
    flag: "--version",
    short: "-v",
    description: "Show the EasyBar version"
  )

  static let helpOption = CLIOption(
    flag: "--help",
    short: "-h",
    description: "Show help"
  )

  static let watchOption = CLIOption(
    flag: "--watch",
    short: "-w",
    description: "Continuously stream metrics and render rolling graphs"
  )

  static let configPathOption = CLIOption(
    flag: "--config",
    description: "Validate this config file instead of the active config",
    placeholder: "path"
  )

  static let logWidgetOption = CLIOption(
    flag: "--widget",
    description: "Match one Lua or native widget",
    placeholder: "name"
  )

  static let logRuntimeOption = CLIOption(
    flag: "--runtime",
    description: "Match the app, Lua, or agent runtime",
    placeholder: "kind"
  )

  static let logLevelOption = CLIOption(
    flag: "--level",
    description: "Match this severity and higher; sets the live follow level",
    placeholder: "level"
  )

  static let logRequestIDOption = CLIOption(
    flag: "--request-id",
    description: "Find one request across retained logs",
    placeholder: "id"
  )

  static let logSinceOption = CLIOption(
    flag: "--since",
    description: "Show entries since a duration or ISO-8601 timestamp",
    placeholder: "time"
  )

  static let logLinesOption = CLIOption(
    flag: "--lines",
    short: "-n",
    description: "Limit the latest matching retained history",
    placeholder: "count"
  )

  static let logAllOption = CLIOption(
    flag: "--all",
    description: "Show all matching retained history"
  )

  static let logFollowOption = CLIOption(
    flag: "--follow",
    short: "-f",
    description: "Subscribe to live app/Lua logs and follow agent files"
  )

  static let jsonOption = CLIOption(
    flag: "--json",
    description: "Print JSON output"
  )

  static let inboxSourceOption = CLIOption(
    flag: "--source",
    description: "Publisher source",
    placeholder: "name"
  )

  static let inboxIDOption = CLIOption(
    flag: "--id",
    description: "Stable message identifier",
    placeholder: "id"
  )

  static let inboxTitleOption = CLIOption(
    flag: "--title",
    description: "Message title",
    placeholder: "text"
  )

  static let inboxMessageOption = CLIOption(
    flag: "--message",
    description: "Optional message body",
    placeholder: "text"
  )

  static let inboxSeverityOption = CLIOption(
    flag: "--severity",
    description: "Message severity: info, success, warning, or error",
    placeholder: "level"
  )

  static let inboxCategoryOption = CLIOption(
    flag: "--category",
    description: "Optional inbox category",
    placeholder: "name"
  )

  static let inboxURLOption = CLIOption(
    flag: "--url",
    description: "Optional HTTP(S) URL opened by the message action",
    placeholder: "url"
  )

  static let inboxReadOption = CLIOption(
    flag: "--read",
    description: "Create the message in the read state"
  )

  static let inboxUnreadOption = CLIOption(
    flag: "--unread",
    description: "List only unread messages"
  )

  static let inboxAllOption = CLIOption(
    flag: "--all",
    description: "Clear every inbox source"
  )

  static let packageSHA256Option = CLIOption(
    flag: "--sha256",
    description: "Expected SHA-256 for a direct archive",
    placeholder: "digest"
  )

  static let packageRegistryOption = CLIOption(
    flag: "--registry",
    description: "Registry index URL or local index.json path",
    placeholder: "source"
  )

  static let packageWidgetsDirectoryOption = CLIOption(
    flag: "--widgets-dir",
    description: "Install into this widget directory",
    placeholder: "path"
  )

  static let packageNoRegistryOption = CLIOption(
    flag: "--no-registry",
    description: "Do not resolve missing dependencies from a registry"
  )

  static let globalOptions = [socketOption, debugOption, versionOption, helpOption]

  static let logOptions = [
    logWidgetOption,
    logRuntimeOption,
    logLevelOption,
    logRequestIDOption,
    logSinceOption,
    logLinesOption,
    logAllOption,
    logFollowOption,
    jsonOption,
  ]

  static let commandGroups: [CLICommandGroup] = [
    .init(name: "refresh", description: "Refresh the bar, widgets, and agent-backed data"),
    .init(name: "logs", description: "Show retained and live process logs"),
    .init(name: "metrics", description: "Show runtime metrics"),
    .init(name: "inbox", description: "Manage native inbox messages"),
    .init(name: "widgets", description: "Install Lua widget packages"),
    .init(name: "config", description: "Reload or validate configuration"),
    .init(name: "runtime", description: "Manage the Lua widget runtime"),
    .init(name: "agent", description: "Manage calendar and network agents"),
    .init(name: "event", description: "Emit EasyBar scripting events"),
  ]

  static let commands: [CLICommandDescriptor] = [
    .init(
      path: ["refresh"],
      description: "Refresh the bar, widgets, and agent-backed data",
      kind: .control(.manualRefresh)
    ),
    .init(
      path: ["logs"],
      description: "Show retained history and optionally subscribe to live records",
      kind: .logs,
      options: logOptions
    ),
    .init(
      path: ["metrics"],
      description: "Print a metrics snapshot or stream live metrics",
      kind: .metrics,
      options: [watchOption]
    ),
    .init(
      path: ["widgets", "install"],
      description: "Install a registry package, local package, or direct archive",
      kind: .installWidgetPackage,
      usageArguments: ["<name|path|url>"],
      options: [
        packageSHA256Option,
        packageRegistryOption,
        packageWidgetsDirectoryOption,
        packageNoRegistryOption,
      ]
    ),
    .init(
      path: ["inbox", "send"],
      description: "Add or update a native inbox message",
      kind: .inbox(.send),
      options: [
        inboxSourceOption, inboxIDOption, inboxTitleOption, inboxMessageOption,
        inboxSeverityOption, inboxCategoryOption, inboxURLOption, inboxReadOption,
      ]
    ),
    .init(
      path: ["inbox", "list"],
      description: "List native inbox messages without changing their state",
      kind: .inbox(.list),
      options: [inboxSourceOption, inboxUnreadOption, jsonOption]
    ),
    .init(
      path: ["inbox", "mark-read"],
      description: "Mark matching inbox messages as read",
      kind: .inbox(.markRead),
      options: [inboxSourceOption, inboxIDOption]
    ),
    .init(
      path: ["inbox", "mark-unread"],
      description: "Mark matching inbox messages as unread",
      kind: .inbox(.markUnread),
      options: [inboxSourceOption, inboxIDOption]
    ),
    .init(
      path: ["inbox", "dismiss"],
      description: "Dismiss matching inbox messages",
      kind: .inbox(.dismiss),
      options: [inboxSourceOption, inboxIDOption]
    ),
    .init(
      path: ["inbox", "remove"],
      description: "Delete one inbox message by source and ID",
      kind: .inbox(.remove),
      options: [inboxSourceOption, inboxIDOption]
    ),
    .init(
      path: ["inbox", "clear"],
      description: "Remove one source or every inbox message",
      kind: .inbox(.clear),
      options: [inboxSourceOption, inboxAllOption]
    ),
    .init(
      path: ["config", "reload"],
      description: "Reload config from disk and rebuild EasyBar",
      kind: .control(.reloadConfig)
    ),
    .init(
      path: ["config", "validate"],
      description: "Ask the running app to validate configuration",
      kind: .validateConfig,
      options: [configPathOption]
    ),
    .init(
      path: ["runtime", "restart"],
      description: "Restart only the Lua widget runtime",
      kind: .control(.restartLuaRuntime)
    ),
    .init(
      path: ["agent", "restart", "calendar"],
      description: "Restart the calendar agent through its socket",
      kind: .restartAgent(.calendar)
    ),
    .init(
      path: ["agent", "restart", "network"],
      description: "Restart the network agent through its socket",
      kind: .restartAgent(.network)
    ),
    .init(
      path: ["agent", "restart", "all"],
      description: "Restart both helper agents and report partial failure",
      kind: .restartAgent(.all)
    ),
    .init(
      path: ["agent", "version", "calendar"],
      description: "Query the running calendar agent version",
      kind: .versionAgent(.calendar),
      options: [jsonOption]
    ),
    .init(
      path: ["agent", "version", "network"],
      description: "Query the running network agent version",
      kind: .versionAgent(.network),
      options: [jsonOption]
    ),
    .init(
      path: ["agent", "version", "all"],
      description: "Show EasyBar and both running agent versions",
      kind: .versionAgent(.all),
      options: [jsonOption]
    ),
    .init(
      path: ["event", "emit"],
      description: "Emit one EasyBar scripting event",
      kind: .emitEvent,
      usageArguments: ["<name>"]
    ),
  ]

  /// Returns the longest command path matching the beginning of `arguments`.
  static func resolveCommand(in arguments: [String]) -> (CLICommandDescriptor, Int)? {
    var best: (CLICommandDescriptor, Int)?

    for command in commands where arguments.starts(with: command.path) {
      if best == nil || command.path.count > best!.1 {
        best = (command, command.path.count)
      }
    }

    return best
  }

  /// Returns the IPC command for one public scripting event name.
  static func eventCommand(for value: String) -> IPC.Command? {
    switch value.replacingOccurrences(of: "-", with: "_") {
    case IPC.Command.workspaceChange.rawValue:
      return .workspaceChange
    case IPC.Command.focusChange.rawValue:
      return .focusChange
    case IPC.Command.spaceModeChange.rawValue:
      return .spaceModeChange
    default:
      return nil
    }
  }

  static func formatRow(_ value: String, _ description: String, width: Int = 28) -> String {
    "  " + value.padding(toLength: width, withPad: " ", startingAt: 0) + description
  }
}
