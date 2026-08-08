import EasyBarShared
import Foundation

/// Parses CLI arguments using the declarative command catalog.
func parseArguments(_ arguments: [String]) throws -> ParsedArguments {
  var global = GlobalOptionState()
  var commandIndex = 1

  while commandIndex < arguments.count {
    guard
      let nextIndex = try parseGlobalArgument(
        arguments[commandIndex],
        arguments: arguments,
        index: commandIndex,
        state: &global,
        helpTopic: []
      )
    else {
      break
    }
    commandIndex = nextIndex
  }

  let commandArguments = Array(arguments.dropFirst(commandIndex))
  guard !commandArguments.isEmpty else {
    throw AppError.message("no command provided")
  }

  guard let (descriptor, consumedCount) = CLI.resolveCommand(in: commandArguments) else {
    if let group = commandArguments.first,
      CLI.commandGroups.contains(where: { $0.name == group })
    {
      throw AppError.showUsage([group])
    }
    throw AppError.message("unknown command '\(commandArguments.joined(separator: " "))'")
  }

  let remaining = Array(commandArguments.dropFirst(consumedCount))
  let action = try parseCommand(
    descriptor,
    arguments: remaining,
    global: &global
  )

  if global.socketPath != nil, !descriptor.kind.acceptsSocketOverride {
    throw AppError.message("--socket cannot be used with \(descriptor.commandText)")
  }

  return ParsedArguments(
    action: action,
    socketPath: global.socketPath,
    debugEnabled: global.debugEnabled
  )
}

private struct GlobalOptionState {
  var socketPath: String?
  var debugEnabled = false
}

/// Parses one option shared by command groups.
///
/// Command-specific parsers call this only after checking their own value options, so a value such
/// as `--debug` remains a value when it follows `--title` or `--message`.
private func parseGlobalArgument(
  _ argument: String,
  arguments: [String],
  index: Int,
  state: inout GlobalOptionState,
  helpTopic: [String]
) throws -> Int? {
  if CLI.helpOption.matches(argument) {
    throw AppError.showUsage(helpTopic)
  }

  if CLI.versionOption.matches(argument) {
    throw AppError.showVersion
  }

  if CLI.debugOption.matches(argument) {
    state.debugEnabled = true
    return index + 1
  }

  if let parsed = try parseValueArgument(
    option: CLI.socketOption,
    argument,
    arguments: arguments,
    index: index
  ) {
    state.socketPath = parsed.value
    return parsed.nextIndex
  }

  return nil
}

private func parseCommand(
  _ descriptor: CLICommandDescriptor,
  arguments: [String],
  global: inout GlobalOptionState
) throws -> CLIAction {
  switch descriptor.kind {
  case .control(let command):
    try parseGlobalOnlyArguments(
      arguments,
      command: descriptor,
      global: &global
    )
    return .control(command)

  case .metrics:
    var watch = false
    var index = 0
    while index < arguments.count {
      let argument = arguments[index]
      if CLI.watchOption.matches(argument) {
        watch = true
        index += 1
        continue
      }
      if let nextIndex = try parseGlobalArgument(
        argument,
        arguments: arguments,
        index: index,
        state: &global,
        helpTopic: descriptor.path
      ) {
        index = nextIndex
        continue
      }
      throw AppError.message("unknown metrics option '\(argument)'")
    }
    return .metrics(watch: watch)

  case .logs:
    return .logs(
      try parseLogOptions(
        arguments,
        command: descriptor,
        global: &global
      )
    )

  case .validateConfig:
    var configPath: String?
    var index = 0
    while index < arguments.count {
      let argument = arguments[index]
      if let parsed = try parseValueArgument(
        option: CLI.configPathOption,
        argument,
        arguments: arguments,
        index: index
      ) {
        configPath = parsed.value
        index = parsed.nextIndex
        continue
      }
      if let nextIndex = try parseGlobalArgument(
        argument,
        arguments: arguments,
        index: index,
        state: &global,
        helpTopic: descriptor.path
      ) {
        index = nextIndex
        continue
      }
      throw AppError.message("unknown config validate option '\(argument)'")
    }
    return .validateConfig(configPath: configPath)

  case .restartAgent(let target):
    try parseGlobalOnlyArguments(
      arguments,
      command: descriptor,
      global: &global
    )
    return .restartAgent(target)

  case .versionAgent(let target):
    var json = false
    var index = 0
    while index < arguments.count {
      let argument = arguments[index]
      if CLI.jsonOption.matches(argument) {
        json = true
        index += 1
        continue
      }
      if let nextIndex = try parseGlobalArgument(
        argument,
        arguments: arguments,
        index: index,
        state: &global,
        helpTopic: descriptor.path
      ) {
        index = nextIndex
        continue
      }
      throw AppError.message("unknown agent version option '\(argument)'")
    }
    return .versionAgent(target, json: json)

  case .emitEvent:
    var eventName: String?
    var index = 0
    while index < arguments.count {
      let argument = arguments[index]
      if let nextIndex = try parseGlobalArgument(
        argument,
        arguments: arguments,
        index: index,
        state: &global,
        helpTopic: descriptor.path
      ) {
        index = nextIndex
        continue
      }
      guard eventName == nil else {
        throw AppError.message("event emit requires exactly one event name")
      }
      eventName = argument
      index += 1
    }
    guard let eventName else {
      throw AppError.message("event emit requires exactly one event name")
    }
    guard let command = CLI.eventCommand(for: eventName) else {
      throw AppError.message("unknown event '\(eventName)'")
    }
    return .control(command)

  case .inbox(let verb):
    return .inbox(
      try parseInboxCommand(
        verb,
        arguments: arguments,
        command: descriptor,
        global: &global
      )
    )

  case .installWidgetPackage:
    return .installWidgetPackage(
      try parseWidgetPackageInstallOptions(
        arguments,
        command: descriptor,
        global: &global
      )
    )

  case .searchWidgetPackages:
    return .searchWidgetPackages(
      try parseWidgetPackageSearchOptions(
        arguments,
        command: descriptor,
        global: &global
      )
    )

  case .outdatedWidgetPackages:
    return .outdatedWidgetPackages(
      registry: try parseWidgetPackageRegistryOnlyOptions(
        arguments,
        command: descriptor,
        global: &global
      )
    )

  case .updateWidgetPackages:
    return .updateWidgetPackages(
      try parseWidgetPackageUpdateOptions(
        arguments,
        command: descriptor,
        global: &global
      )
    )

  case .uninstallWidgetPackage:
    return .uninstallWidgetPackage(
      try parseWidgetPackageUninstallName(
        arguments,
        command: descriptor,
        global: &global
      )
    )
  }
}

private func parseWidgetPackageRegistryOnlyOptions(
  _ arguments: [String],
  command: CLICommandDescriptor,
  global: inout GlobalOptionState
) throws -> String? {
  var registry: String?
  var index = 0

  while index < arguments.count {
    let argument = arguments[index]
    if let parsed = try parseValueArgument(
      option: CLI.packageRegistryOption,
      argument,
      arguments: arguments,
      index: index
    ) {
      registry = parsed.value
      index = parsed.nextIndex
      continue
    }
    if let nextIndex = try parseGlobalArgument(
      argument,
      arguments: arguments,
      index: index,
      state: &global,
      helpTopic: command.path
    ) {
      index = nextIndex
      continue
    }
    throw AppError.message("unknown \(command.commandText) option '\(argument)'")
  }

  return registry
}

private func parseWidgetPackageUpdateOptions(
  _ arguments: [String],
  command: CLICommandDescriptor,
  global: inout GlobalOptionState
) throws -> WidgetPackageUpdateOptions {
  var name: String?
  var updateAll = false
  var registry: String?
  var index = 0

  while index < arguments.count {
    let argument = arguments[index]
    if CLI.packageUpdateAllOption.matches(argument) {
      updateAll = true
      index += 1
      continue
    }
    if let parsed = try parseValueArgument(
      option: CLI.packageRegistryOption,
      argument,
      arguments: arguments,
      index: index
    ) {
      registry = parsed.value
      index = parsed.nextIndex
      continue
    }
    if let nextIndex = try parseGlobalArgument(
      argument,
      arguments: arguments,
      index: index,
      state: &global,
      helpTopic: command.path
    ) {
      index = nextIndex
      continue
    }
    guard !argument.hasPrefix("-") else {
      throw AppError.message("unknown widgets update option '\(argument)'")
    }
    guard name == nil else {
      throw AppError.message("widgets update accepts exactly one package name or --all")
    }
    name = argument
    index += 1
  }

  let selection: WidgetPackageUpdateSelection
  if updateAll, name == nil {
    selection = .all
  } else if !updateAll, let name {
    selection = .package(name)
  } else {
    throw AppError.message("widgets update requires exactly one package name or --all")
  }
  return WidgetPackageUpdateOptions(selection: selection, registry: registry)
}

private func parseWidgetPackageUninstallName(
  _ arguments: [String],
  command: CLICommandDescriptor,
  global: inout GlobalOptionState
) throws -> String {
  var name: String?
  var index = 0

  while index < arguments.count {
    let argument = arguments[index]
    if let nextIndex = try parseGlobalArgument(
      argument,
      arguments: arguments,
      index: index,
      state: &global,
      helpTopic: command.path
    ) {
      index = nextIndex
      continue
    }
    guard !argument.hasPrefix("-") else {
      throw AppError.message("unknown widgets uninstall option '\(argument)'")
    }
    guard name == nil else {
      throw AppError.message("widgets uninstall requires exactly one package name")
    }
    name = argument
    index += 1
  }

  guard let name, !name.isEmpty else {
    throw AppError.message("widgets uninstall requires a package name")
  }
  return name
}

private func parseWidgetPackageSearchOptions(
  _ arguments: [String],
  command: CLICommandDescriptor,
  global: inout GlobalOptionState
) throws -> WidgetPackageSearchOptions {
  var query: String?
  var registry: String?
  var index = 0

  while index < arguments.count {
    let argument = arguments[index]
    if let parsed = try parseValueArgument(
      option: CLI.packageRegistryOption,
      argument,
      arguments: arguments,
      index: index
    ) {
      registry = parsed.value
      index = parsed.nextIndex
      continue
    }
    if let nextIndex = try parseGlobalArgument(
      argument,
      arguments: arguments,
      index: index,
      state: &global,
      helpTopic: command.path
    ) {
      index = nextIndex
      continue
    }
    guard !argument.hasPrefix("-") else {
      throw AppError.message("unknown widgets search option '\(argument)'")
    }
    guard query == nil else {
      throw AppError.message("widgets search accepts at most one query")
    }
    query = argument
    index += 1
  }

  return WidgetPackageSearchOptions(query: query, registry: registry)
}

private func parseWidgetPackageInstallOptions(
  _ arguments: [String],
  command: CLICommandDescriptor,
  global: inout GlobalOptionState
) throws -> WidgetPackageInstallOptions {
  var source: String?
  var sha256: String?
  var registry: String?
  var useRegistry = true
  var index = 0

  while index < arguments.count {
    let argument = arguments[index]
    if let parsed = try parseValueArgument(
      option: CLI.packageSHA256Option,
      argument,
      arguments: arguments,
      index: index
    ) {
      sha256 = parsed.value
      index = parsed.nextIndex
      continue
    }
    if let parsed = try parseValueArgument(
      option: CLI.packageRegistryOption,
      argument,
      arguments: arguments,
      index: index
    ) {
      registry = parsed.value
      index = parsed.nextIndex
      continue
    }
    if CLI.packageNoRegistryOption.matches(argument) {
      useRegistry = false
      index += 1
      continue
    }
    if let nextIndex = try parseGlobalArgument(
      argument,
      arguments: arguments,
      index: index,
      state: &global,
      helpTopic: command.path
    ) {
      index = nextIndex
      continue
    }
    guard !argument.hasPrefix("-") else {
      throw AppError.message("unknown widgets install option '\(argument)'")
    }
    guard source == nil else {
      throw AppError.message("widgets install requires exactly one package source")
    }
    source = argument
    index += 1
  }

  guard let source, !source.isEmpty else {
    throw AppError.message("widgets install requires a package name, path, or URL")
  }
  if !useRegistry, registry != nil {
    throw AppError.message("--registry and --no-registry cannot be used together")
  }
  return WidgetPackageInstallOptions(
    source: source,
    sha256: sha256,
    registry: registry,
    useRegistry: useRegistry
  )
}

private func parseGlobalOnlyArguments(
  _ arguments: [String],
  command: CLICommandDescriptor,
  global: inout GlobalOptionState
) throws {
  var index = 0
  while index < arguments.count {
    let argument = arguments[index]
    if let nextIndex = try parseGlobalArgument(
      argument,
      arguments: arguments,
      index: index,
      state: &global,
      helpTopic: command.path
    ) {
      index = nextIndex
      continue
    }
    throw AppError.message("\(command.commandText) does not accept '\(argument)'")
  }
}

/// Parses options accepted by `easybar logs`.
private func parseLogOptions(
  _ arguments: [String],
  command: CLICommandDescriptor,
  global: inout GlobalOptionState
) throws -> LogCommandOptions {
  var state = LogCommandOptionState()
  var index = 0

  while index < arguments.count {
    let argument = arguments[index]

    if let parsed = try parseValueArgument(
      option: CLI.logWidgetOption,
      argument,
      arguments: arguments,
      index: index
    ) {
      state.options.widget = parsed.value
      index = parsed.nextIndex
      continue
    }

    if let parsed = try parseValueArgument(
      option: CLI.logRuntimeOption,
      argument,
      arguments: arguments,
      index: index
    ) {
      let normalized = parsed.value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      let runtime: ProcessLogRuntime?
      switch normalized {
      case "app":
        runtime = .native
      case "lua":
        runtime = .lua
      case "agent":
        runtime = .agent
      default:
        runtime = nil
      }
      guard let runtime else {
        throw AppError.message("--runtime expects app, lua, or agent")
      }
      state.options.runtime = runtime
      index = parsed.nextIndex
      continue
    }

    if let parsed = try parseValueArgument(
      option: CLI.logLevelOption,
      argument,
      arguments: arguments,
      index: index
    ) {
      guard let level = ProcessLogLevel.normalized(parsed.value) else {
        throw AppError.message("--level expects trace, debug, info, warn, or error")
      }
      state.options.minimumLevel = level
      index = parsed.nextIndex
      continue
    }

    if let parsed = try parseValueArgument(
      option: CLI.logRequestIDOption,
      argument,
      arguments: arguments,
      index: index
    ) {
      state.options.requestID = parsed.value
      index = parsed.nextIndex
      continue
    }

    if let parsed = try parseValueArgument(
      option: CLI.logSinceOption,
      argument,
      arguments: arguments,
      index: index
    ) {
      state.options.since = parsed.value
      index = parsed.nextIndex
      continue
    }

    if let parsed = try parseValueArgument(
      option: CLI.logLinesOption,
      argument,
      arguments: arguments,
      index: index
    ) {
      guard let count = Int(parsed.value), count > 0 else {
        throw AppError.message("--lines expects a positive integer")
      }
      state.options.historyLimit = count
      state.linesSpecified = true
      index = parsed.nextIndex
      continue
    }

    if CLI.logAllOption.matches(argument) {
      state.allHistory = true
      index += 1
      continue
    }

    if CLI.logFollowOption.matches(argument) {
      state.options.follow = true
      index += 1
      continue
    }

    if CLI.jsonOption.matches(argument) {
      state.options.json = true
      index += 1
      continue
    }

    if let nextIndex = try parseGlobalArgument(
      argument,
      arguments: arguments,
      index: index,
      state: &global,
      helpTopic: command.path
    ) {
      index = nextIndex
      continue
    }

    throw AppError.message("unknown logs option '\(argument)'")
  }

  return try state.finalize()
}

/// Parses one native inbox command using the options declared by its command descriptor.
private func parseInboxCommand(
  _ verb: InboxCLIVerb,
  arguments: [String],
  command: CLICommandDescriptor,
  global: inout GlobalOptionState
) throws -> InboxCLICommand {
  let valueOptions = [
    CLI.inboxSourceOption,
    CLI.inboxIDOption,
    CLI.inboxTitleOption,
    CLI.inboxMessageOption,
    CLI.inboxSeverityOption,
    CLI.inboxCategoryOption,
    CLI.inboxURLOption,
  ]
  let flagOptions = [
    CLI.jsonOption,
    CLI.inboxUnreadOption,
    CLI.inboxReadOption,
    CLI.inboxAllOption,
  ]

  var values: [String: String] = [:]
  var flags = Set<String>()
  var index = 0

  while index < arguments.count {
    let argument = arguments[index]

    if let option = flagOptions.first(where: { $0.matches(argument) }) {
      flags.insert(option.flag)
      index += 1
      continue
    }

    var matchedValue = false
    for option in valueOptions {
      if let parsed = try parseValueArgument(
        option: option,
        argument,
        arguments: arguments,
        index: index
      ) {
        values[option.flag] = parsed.value
        index = parsed.nextIndex
        matchedValue = true
        break
      }
    }
    if matchedValue {
      continue
    }

    if let nextIndex = try parseGlobalArgument(
      argument,
      arguments: arguments,
      index: index,
      state: &global,
      helpTopic: command.path
    ) {
      index = nextIndex
      continue
    }

    throw AppError.message("unknown inbox option '\(argument)'")
  }

  func rejectUnused(
    allowedValues: Set<String>,
    allowedFlags: Set<String> = []
  ) throws {
    if let option = values.keys.sorted().first(where: { !allowedValues.contains($0) }) {
      throw AppError.message("\(option) cannot be used with inbox \(verb.rawValue)")
    }
    if let flag = flags.sorted().first(where: { !allowedFlags.contains($0) }) {
      throw AppError.message("\(flag) cannot be used with inbox \(verb.rawValue)")
    }
  }

  switch verb {
  case .send:
    try rejectUnused(
      allowedValues: [
        CLI.inboxSourceOption.flag,
        CLI.inboxIDOption.flag,
        CLI.inboxTitleOption.flag,
        CLI.inboxMessageOption.flag,
        CLI.inboxSeverityOption.flag,
        CLI.inboxCategoryOption.flag,
        CLI.inboxURLOption.flag,
      ],
      allowedFlags: [CLI.inboxReadOption.flag]
    )
    guard let source = values[CLI.inboxSourceOption.flag] else {
      throw AppError.message("inbox send requires --source")
    }
    guard let title = values[CLI.inboxTitleOption.flag] else {
      throw AppError.message("inbox send requires --title")
    }
    let severityValue = values[CLI.inboxSeverityOption.flag] ?? IPC.InboxSeverity.info.rawValue
    guard let severity = IPC.InboxSeverity(rawValue: severityValue.lowercased()) else {
      throw AppError.message("--severity expects info, success, warning, or error")
    }
    return .send(
      IPC.InboxItem(
        source: source,
        id: values[CLI.inboxIDOption.flag] ?? UUID().uuidString.lowercased(),
        title: title,
        message: values[CLI.inboxMessageOption.flag],
        severity: severity,
        group: values[CLI.inboxCategoryOption.flag],
        url: values[CLI.inboxURLOption.flag],
        timestamp: Date().timeIntervalSince1970,
        unread: !flags.contains(CLI.inboxReadOption.flag)
      )
    )

  case .list:
    try rejectUnused(
      allowedValues: [CLI.inboxSourceOption.flag],
      allowedFlags: [CLI.jsonOption.flag, CLI.inboxUnreadOption.flag]
    )
    return .list(
      source: values[CLI.inboxSourceOption.flag],
      unreadOnly: flags.contains(CLI.inboxUnreadOption.flag),
      json: flags.contains(CLI.jsonOption.flag)
    )

  case .markRead, .markUnread, .dismiss:
    try rejectUnused(
      allowedValues: [CLI.inboxSourceOption.flag, CLI.inboxIDOption.flag]
    )
    guard let source = values[CLI.inboxSourceOption.flag] else {
      throw AppError.message("inbox \(verb.rawValue) requires --source")
    }
    let id = values[CLI.inboxIDOption.flag]
    switch verb {
    case .markRead:
      return .markRead(source: source, id: id)
    case .markUnread:
      return .markUnread(source: source, id: id)
    case .dismiss:
      return .dismiss(source: source, id: id)
    default:
      preconditionFailure("unexpected inbox verb")
    }

  case .remove:
    try rejectUnused(
      allowedValues: [CLI.inboxSourceOption.flag, CLI.inboxIDOption.flag]
    )
    guard let source = values[CLI.inboxSourceOption.flag],
      let id = values[CLI.inboxIDOption.flag]
    else {
      throw AppError.message("inbox remove requires --source and --id")
    }
    return .remove(source: source, id: id)

  case .clear:
    try rejectUnused(
      allowedValues: [CLI.inboxSourceOption.flag],
      allowedFlags: [CLI.inboxAllOption.flag]
    )
    let source = values[CLI.inboxSourceOption.flag]
    let clearAll = flags.contains(CLI.inboxAllOption.flag)
    guard source != nil || clearAll else {
      throw AppError.message("inbox clear requires --source or --all")
    }
    guard !(source != nil && clearAll) else {
      throw AppError.message("inbox clear accepts either --source or --all, not both")
    }
    return .clear(source: source)
  }
}

/// Parses one `--flag value` or `--flag=value` option.
private func parseValueArgument(
  option: CLIOption,
  _ argument: String,
  arguments: [String],
  index: Int
) throws -> (value: String, nextIndex: Int)? {
  if let value = option.inlineValue(from: argument) {
    guard !value.isEmpty else {
      throw AppError.message("missing value for \(option.flag)")
    }
    return (value, index + 1)
  }

  guard option.matches(argument) else {
    return nil
  }

  let nextIndex = index + 1
  guard nextIndex < arguments.count else {
    throw AppError.message("missing value for \(argument)")
  }

  let value = arguments[nextIndex]
  guard !value.isEmpty else {
    throw AppError.message("missing value for \(argument)")
  }

  return (value, nextIndex + 1)
}
