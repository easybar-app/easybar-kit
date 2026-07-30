import EasyBarShared
import Foundation

extension MetricsRenderer {
  /// Renders EasyBar and Lua process metrics.
  static func processes(_ snapshot: IPC.MetricsSnapshot) -> String {
    let lines = [
      "Processes",
      processHeader(),
      processLine(snapshot.process),
      processLine(snapshot.lua),
    ]
    return lines.joined(separator: "\n")
  }

  /// Renders the global event names forwarded to the Lua runtime.
  static func subscriptions(_ snapshot: IPC.MetricsSnapshot) -> String {
    guard let events = snapshot.runtime.subscribedEvents else { return "" }
    guard !events.isEmpty else { return "Subscribed events\nnone" }

    return (["Subscribed events (\(events.count))"] + events.map { "- \(subscription($0))" })
      .joined(separator: "\n")
  }

  /// Formats internal timer subscription keys as widget-oriented intervals.
  static func subscription(_ event: String, compact: Bool = false) -> String {
    let parts = event.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
    guard parts.count == 3,
      parts[0] == "interval_tick",
      !parts[1].isEmpty,
      let seconds = Double(parts[2]),
      seconds.isFinite,
      seconds > 0
    else {
      return event
    }

    let interval = duration(seconds)
    return compact ? "\(parts[1]) (\(interval))" : "\(parts[1]) (every \(interval))"
  }

  /// Formats one positive interval using the largest exact unit.
  static func duration(_ seconds: Double) -> String {
    if seconds.truncatingRemainder(dividingBy: 3600) == 0 {
      return "\(compactNumber(seconds / 3600))h"
    }
    if seconds.truncatingRemainder(dividingBy: 60) == 0 {
      return "\(compactNumber(seconds / 60))m"
    }
    return "\(compactNumber(seconds))s"
  }

  /// Formats interval values without a redundant decimal for whole numbers.
  static func compactNumber(_ value: Double) -> String {
    guard value.isFinite else { return "-" }

    if value.rounded() == value {
      return String(format: "%.0f", value)
    }
    return number(value)
  }

  /// Renders runtime counters and rates.
  static func runtime(_ snapshot: IPC.MetricsSnapshot) -> String {
    let runtime = snapshot.runtime

    var lines = [
      "Runtime",
      row([
        column("metric", width: 16),
        column("value", width: 18),
        column("metric", width: 16),
        column("value", width: 18),
      ]),
      row([
        column("subscribers", width: 16),
        column(String(runtime.subscriberCount), width: 18),
        column("lua_ready", width: 16),
        column(yesNo(runtime.luaReady), width: 18),
      ]),
      row([
        column("subscribed", width: 16),
        column(String(runtime.subscribedEventCount), width: 18),
        column("lua_restarts", width: 16),
        column(String(runtime.luaRestartCount), width: 18),
      ]),
      row([
        column("events", width: 16),
        column(String(runtime.totalEvents), width: 18),
        column("events_rate", width: 16),
        column("\(number(runtime.eventsPerSecond))/s", width: 18),
      ]),
      row([
        column("dropped", width: 16),
        column(String(runtime.droppedEvents), width: 18),
        column("dropped_rate", width: 16),
        column("\(number(runtime.droppedEventsPerSecond))/s", width: 18),
      ]),
      row([
        column("coalesced", width: 16),
        column(String(runtime.coalescedEvents), width: 18),
        column("coal_rate", width: 16),
        column("\(number(runtime.coalescedEventsPerSecond))/s", width: 18),
      ]),
      row([
        column("app/widget", width: 16),
        column("\(runtime.appEvents)/\(runtime.widgetEvents)", width: 18),
        column("tree_updates", width: 16),
        column(String(runtime.treeUpdates), width: 18),
      ]),
      row([
        column("tree_rate", width: 16),
        column("\(number(runtime.treeUpdatesPerSecond))/s", width: 18),
        column("decode_errors", width: 16),
        column(String(runtime.decodeErrors), width: 18),
      ]),
      row([
        column("input_overflow", width: 16),
        column(String(runtime.luaRuntimeInputOverflows), width: 18),
        column("event_overflow", width: 16),
        column(String(runtime.luaEventQueueOverflows), width: 18),
      ]),
      row([
        column("event_queue", width: 16),
        column(String(runtime.luaEventQueueDepth), width: 18),
        column(
          runtime.luaLogLines == nil ? "lua_stderr" : "lua_logs",
          width: 16
        ),
        column(
          String(runtime.luaLogLines ?? runtime.stderrLines),
          width: 18
        ),
      ]),
      row([
        column("lua_reads", width: 16),
        column(String(runtime.transportLines), width: 18),
        column("lua_writes", width: 16),
        column(String(runtime.luaWrites), width: 18),
      ]),
    ]

    if let warningLines = runtime.luaWarningLines,
      let errorLines = runtime.luaErrorLines,
      let rawStderrLines = runtime.luaRawStderrLines
    {
      lines.append(
        row([
          column("lua_warn", width: 16),
          column(String(warningLines), width: 18),
          column("lua_error", width: 16),
          column(String(errorLines), width: 18),
        ])
      )
      lines.append(
        row([
          column("lua_raw_stderr", width: 16),
          column(String(rawStderrLines), width: 18),
          column("", width: 16),
          column("", width: 18),
        ])
      )
    }

    lines.append(
      row([
        column("last_tree", width: 16),
        column(runtime.lastTreeRoot ?? "-", width: 18),
        column("tree_nodes", width: 16),
        column(runtime.lastTreeNodeCount.map(String.init) ?? "-", width: 18),
      ])
    )
    lines.append(
      row([
        column("last_tree_age", width: 16),
        column(relative(runtime.lastTreeAt), width: 18),
        column("sample", width: 16),
        column(sampleInterval(snapshot.sampleIntervalSeconds), width: 18),
      ])
    )

    return lines.joined(separator: "\n")
  }

  /// Renders per-agent connection and process metrics.
  static func agents(_ snapshot: IPC.MetricsSnapshot) -> String {
    let header = row([
      column("name", width: 10),
      column("conn", width: 6),
      column("pid", width: 7),
      column("cpu", width: 8),
      column("mem", width: 10),
      column("thr", width: 5),
      column("msgs", width: 11),
      column("reconn", width: 6),
      column("refresh", width: 7),
      column("decode", width: 6),
    ])

    let body = snapshot.agents.map { agent in
      row([
        column(agent.name, width: 10),
        column(yesNo(agent.connected), width: 6),
        column(agent.process.pid.map(String.init) ?? "-", width: 7),
        column(percent(agent.process.cpuPercent), width: 8),
        column(bytes(agent.process.residentSizeBytes), width: 10),
        column(agent.process.threadCount.map(String.init) ?? "-", width: 5),
        column("\(agent.messagesTotal) (\(number(agent.messagesPerSecond))/s)", width: 11),
        column(String(agent.reconnectsTotal), width: 6),
        column(String(agent.refreshesTotal), width: 7),
        column(String(agent.decodeErrorsTotal), width: 6),
      ])
    }

    return (["Agents", header] + body).joined(separator: "\n")
  }

  /// Renders per-widget update metrics.
  static func widgets(_ snapshot: IPC.MetricsSnapshot) -> String {
    guard !snapshot.widgets.isEmpty else {
      return "Widget trees (top 8)\nnone"
    }

    let header = row([
      column("id", width: 24),
      column("updates", width: 12),
      column("nodes", width: 6),
      column("last", width: 6),
    ])

    let body = snapshot.widgets.map { widget in
      row([
        column(widget.id, width: 24),
        column("\(widget.updatesTotal) (\(number(widget.updatesPerSecond))/s)", width: 12),
        column(String(widget.lastNodeCount), width: 6),
        column(relative(widget.lastUpdatedAt), width: 6),
      ])
    }

    return (["Widget trees (top 8)", header] + body).joined(separator: "\n")
  }

  /// Renders per-event totals, rates, drops, and coalescing counts.
  static func events(_ snapshot: IPC.MetricsSnapshot) -> String {
    guard !snapshot.events.isEmpty else {
      return "Events (top 8)\nnone"
    }

    let header = row([
      column("name", width: 18),
      column("total", width: 6),
      column("rate", width: 10),
      column("drop", width: 6),
      column("coal", width: 6),
    ])

    let body = snapshot.events.map { event in
      row([
        column(event.name, width: 18),
        column(String(event.total), width: 6),
        column("\(number(event.perSecond))/s", width: 10),
        column(String(event.droppedTotal), width: 6),
        column(String(event.coalescedTotal), width: 6),
      ])
    }

    return (["Events (top 8)", header] + body).joined(separator: "\n")
  }

}
