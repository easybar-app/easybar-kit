import EasyBarShared
import Foundation

/// Prints retained EasyBar logs and optionally follows live records until interrupted.
func showLogs(
  options: LogCommandOptions,
  explicitSocketPath: String?,
  context: AppContext
) throws {
  let runtimeConfig: SharedRuntimeConfig
  do {
    runtimeConfig = try SharedRuntimeConfig.load()
  } catch {
    throw AppError.message(
      "failed to resolve logging configuration: \(error.localizedDescription)"
    )
  }

  let directory = runtimeConfig.logging.directory
  let since = try parsedLogSince(options.since)
  let filter = ProcessLogFilter(
    widget: options.widget,
    runtime: options.runtime,
    minimumLevel: options.minimumLevel,
    requestID: options.requestID,
    since: since
  )

  context.debug("reading EasyBar logs from \(directory)")

  guard options.follow else {
    guard ProcessLogStore.hasLogs(in: directory) else {
      throw noProcessLogsError(directory: directory)
    }
    let history = try ProcessLogStore.history(
      in: directory,
      filter: filter,
      limit: options.historyLimit
    )
    printLogRecords(history, json: options.json)
    return
  }

  let endpoints = try liveLogEndpoints(
    runtime: options.runtime,
    explicitSocketPath: explicitSocketPath,
    runtimeConfig: runtimeConfig,
    context: context
  )
  let subscription = IPC.LogSubscription(
    widget: options.widget,
    runtime: options.runtime,
    minimumLevel: options.minimumLevel,
    requestID: options.requestID
  )
  var retainedOverlapCounts: [String: Int] = [:]

  try LogStreamClient(endpoints: endpoints).stream(
    subscription: subscription,
    onSubscribed: {
      let history = try retainedLogHistory(
        directory: directory,
        filter: filter,
        limit: options.historyLimit
      )
      printLogRecords(history, json: options.json)
      retainedOverlapCounts = Dictionary(
        history.map { (liveOverlapKey(for: $0), 1) },
        uniquingKeysWith: +
      )
    },
    onRecord: { record in
      let key = liveOverlapKey(for: record)
      if let count = retainedOverlapCounts[key], count > 0 {
        if count == 1 {
          retainedOverlapCounts.removeValue(forKey: key)
        } else {
          retainedOverlapCounts[key] = count - 1
        }
        return
      }
      printLogRecords([record], json: options.json)
    }
  )
}

/// Resolves every process socket required by one live-log filter.
private func liveLogEndpoints(
  runtime: ProcessLogRuntime?,
  explicitSocketPath: String?,
  runtimeConfig: SharedRuntimeConfig,
  context: AppContext
) throws -> [LogStreamEndpoint] {
  if explicitSocketPath != nil, runtime == nil || runtime == .agent {
    throw AppError.message(
      "--socket can only override live logs for --runtime lua or --runtime native"
    )
  }

  let easyBarPath = explicitSocketPath ?? runtimeConfig.easyBar.socketPath
  let endpoints: [LogStreamEndpoint]

  switch runtime {
  case .lua, .native:
    endpoints = [.easyBar(path: easyBarPath)]

  case .agent:
    endpoints = enabledAgentLogEndpoints(runtimeConfig)
    guard !endpoints.isEmpty else {
      throw AppError.message("live agent logs requested, but both agents are disabled")
    }

  case nil:
    endpoints = [.easyBar(path: easyBarPath)] + enabledAgentLogEndpoints(runtimeConfig)
  }

  for endpoint in endpoints {
    context.debug("subscribing to \(endpoint.label) logs at \(endpoint.path)")
  }
  return endpoints
}

/// Returns live-log endpoints for the enabled helper agents.
private func enabledAgentLogEndpoints(
  _ runtimeConfig: SharedRuntimeConfig
) -> [LogStreamEndpoint] {
  var endpoints: [LogStreamEndpoint] = []
  if runtimeConfig.calendarAgent.enabled {
    endpoints.append(.calendarAgent(path: runtimeConfig.calendarAgent.socketPath))
  }
  if runtimeConfig.networkAgent.enabled {
    endpoints.append(.networkAgent(path: runtimeConfig.networkAgent.socketPath))
  }
  return endpoints
}

/// Builds a stable identity used to suppress history/live overlap after subscribing.
private func liveOverlapKey(for record: ProcessLogRecord) -> String {
  [
    record.source,
    record.timestampText ?? "",
    record.level?.rawValue ?? "",
    record.message,
    record.fields["request_id"] ?? "",
    record.widget ?? "",
  ].joined(separator: "\u{1F}")
}

/// Parses one optional `--since` value.
private func parsedLogSince(_ value: String?) throws -> Date? {
  guard let value else { return nil }
  guard let parsed = ProcessLogSinceParser.parse(value) else {
    throw AppError.message(
      "--since expects a duration such as 30m or an ISO-8601 timestamp"
    )
  }
  return parsed
}

/// Loads retained history when any known process log exists.
private func retainedLogHistory(
  directory: String,
  filter: ProcessLogFilter,
  limit: Int?
) throws -> [ProcessLogRecord] {
  guard ProcessLogStore.hasLogs(in: directory) else { return [] }
  return try ProcessLogStore.history(in: directory, filter: filter, limit: limit)
}

/// Returns the standard missing-log error.
private func noProcessLogsError(directory: String) -> AppError {
  AppError.message(
    "no EasyBar process logs found in \(directory); enable [logging].enabled and start EasyBar"
  )
}

/// Prints records in plain structured-text or JSON Lines format.
private func printLogRecords(_ records: [ProcessLogRecord], json: Bool) {
  for record in records {
    let line = json ? jsonLogLine(record) : "[\(record.source)] \(record.rawLine)"
    fputs(line + "\n", stdout)
  }
  if !records.isEmpty {
    fflush(stdout)
  }
}

/// Encodes one parsed record as a stable JSON object.
private func jsonLogLine(_ record: ProcessLogRecord) -> String {
  var object: [String: Any] = [
    "source": record.source,
    "message": record.message,
    "fields": record.fields,
  ]
  if let timestamp = record.timestampText {
    object["timestamp"] = timestamp
  }
  if let level = record.level {
    object["level"] = level.rawValue
  }
  if let runtime = record.runtime {
    object["runtime"] = runtime.rawValue
  }
  if let widget = record.widget {
    object["widget"] = widget
  }

  guard
    let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
    let text = String(data: data, encoding: .utf8)
  else { return #"{"message":"failed to encode log record"}"# }
  return text
}
