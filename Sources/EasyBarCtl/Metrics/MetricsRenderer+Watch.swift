import EasyBarShared
import Foundation

extension MetricsRenderer {
  /// Renders the live dashboard as side-by-side tiles.
  static func wideWatchDashboard(
    _ snapshot: IPC.MetricsSnapshot,
    terminalWidth: Int
  ) -> String {
    // Avoid writing into the final terminal column, which can trigger an extra wrapped line.
    let layoutWidth = min(wideWatchMaximumWidth - 1, terminalWidth - 1)
    let pairGap = 2
    let pairWidth = max(32, (layoutWidth - pairGap) / 2)
    let tileGap = 2
    let tileWidth = max(24, (layoutWidth - tileGap * 2) / 3)

    return [
      tileRow(
        [
          watchProcesses(snapshot),
          watchAgentActivity(snapshot),
        ],
        widths: [pairWidth, pairWidth],
        gap: pairGap
      ),
      tileRow(
        [
          watchRuntime(snapshot, width: tileWidth),
          watchLua(snapshot, width: tileWidth),
          watchDelivery(snapshot, width: tileWidth),
        ],
        widths: [tileWidth, tileWidth, tileWidth],
        gap: tileGap
      ),
      tileRow(
        [
          watchSubscriptions(snapshot, width: tileWidth),
          watchWidgets(snapshot, width: tileWidth),
          watchEvents(snapshot, width: tileWidth),
        ],
        widths: [tileWidth, tileWidth, tileWidth],
        gap: tileGap
      ),
    ].joined(separator: "\n\n")
  }

  /// Renders the same compact live tiles vertically for narrow terminals.
  static func narrowWatchDashboard(
    _ snapshot: IPC.MetricsSnapshot,
    terminalWidth: Int
  ) -> String {
    let width = max(44, terminalWidth)
    return [
      watchProcesses(snapshot),
      watchAgentActivity(snapshot),
      watchRuntime(snapshot, width: width),
      watchLua(snapshot, width: width),
      watchDelivery(snapshot, width: width),
      watchSubscriptions(snapshot, width: width),
      watchWidgets(snapshot, width: width),
      watchEvents(snapshot, width: width),
    ].filter { !$0.isEmpty }.joined(separator: "\n\n")
  }

  /// Renders process resource usage for EasyBar, Lua, and both helper agents.
  static func watchProcesses(_ snapshot: IPC.MetricsSnapshot) -> String {
    let processLines =
      [processLine(snapshot.process), processLine(snapshot.lua)]
      + snapshot.agents.map { processLine($0.process, name: $0.name) }
    return (["Processes", processHeader()] + processLines)
      .joined(separator: "\n")
  }

  /// Renders helper-agent connection and activity counters without repeating process resources.
  static func watchAgentActivity(_ snapshot: IPC.MetricsSnapshot) -> String {
    let header = row([
      column("agent", width: 9),
      column("conn", width: 4),
      column("msgs", width: 10),
      column("rec", width: 4),
      column("ref", width: 4),
      column("err", width: 4),
    ])
    let body = snapshot.agents.map { agent in
      row([
        column(agent.name, width: 9),
        column(yesNo(agent.connected), width: 4),
        column("\(agent.messagesTotal) \(number(agent.messagesPerSecond))/s", width: 10),
        column(String(agent.reconnectsTotal), width: 4),
        column(String(agent.refreshesTotal), width: 4),
        column(String(agent.decodeErrorsTotal), width: 4),
      ])
    }
    return (["Agent activity", header] + body).joined(separator: "\n")
  }

  /// Renders runtime lifecycle status.
  static func watchRuntime(_ snapshot: IPC.MetricsSnapshot, width: Int) -> String {
    let runtime = snapshot.runtime
    return [
      "Runtime",
      compactMetric("metrics clients", String(runtime.subscriberCount), width: width),
      compactMetric("Lua ready", yesNo(runtime.luaReady), width: width),
      compactMetric("Lua restarts", String(runtime.luaRestartCount), width: width),
      compactMetric("subscriptions", String(runtime.subscribedEventCount), width: width),
      compactMetric("sample", sampleInterval(snapshot.sampleIntervalSeconds), width: width),
    ].joined(separator: "\n")
  }

  /// Renders Lua transport, structured log, and input health counters.
  static func watchLua(_ snapshot: IPC.MetricsSnapshot, width: Int) -> String {
    let runtime = snapshot.runtime
    let warningAndErrors = "\(runtime.luaWarningLines)/\(runtime.luaErrorLines)"

    return [
      "Lua",
      compactMetric(
        "reads/writes",
        "\(runtime.transportLines)/\(runtime.luaWrites)",
        width: width
      ),
      compactMetric("logs", String(runtime.luaLogLines), width: width),
      compactMetric("warn/error", warningAndErrors, width: width),
      compactMetric("raw stderr", String(runtime.luaRawStderrLines), width: width),
      compactMetric("decode errors", String(runtime.decodeErrors), width: width),
      compactMetric(
        "input overflow",
        String(runtime.luaRuntimeInputOverflows),
        width: width
      ),
    ].joined(separator: "\n")
  }

  /// Renders event delivery and widget-tree publication counters.
  static func watchDelivery(_ snapshot: IPC.MetricsSnapshot, width: Int) -> String {
    let runtime = snapshot.runtime
    return [
      "Delivery",
      compactMetric(
        "events",
        "\(runtime.totalEvents) (\(number(runtime.eventsPerSecond))/s)",
        width: width
      ),
      compactMetric("app/widget", "\(runtime.appEvents)/\(runtime.widgetEvents)", width: width),
      compactMetric(
        "dropped",
        "\(runtime.droppedEvents) (\(number(runtime.droppedEventsPerSecond))/s)",
        width: width
      ),
      compactMetric(
        "coalesced",
        "\(runtime.coalescedEvents) (\(number(runtime.coalescedEventsPerSecond))/s)",
        width: width
      ),
      compactMetric(
        "queue/overflow",
        "\(runtime.luaEventQueueDepth)/\(runtime.luaEventQueueOverflows)",
        width: width
      ),
      compactMetric(
        "tree updates",
        "\(runtime.treeUpdates) (\(number(runtime.treeUpdatesPerSecond))/s)",
        width: width
      ),
    ].joined(separator: "\n")
  }

  /// Renders every global Lua event subscription in one compact tile.
  static func watchSubscriptions(_ snapshot: IPC.MetricsSnapshot, width _: Int) -> String {
    let events = snapshot.runtime.subscribedEvents
    guard !events.isEmpty else { return "Subscriptions\nnone" }

    return (["Subscriptions (\(events.count))"] + events.map { subscription($0, compact: true) })
      .joined(separator: "\n")
  }

  /// Renders the busiest widget trees using compact aligned columns.
  static func watchWidgets(_ snapshot: IPC.MetricsSnapshot, width: Int) -> String {
    guard !snapshot.widgets.isEmpty else { return "Widget trees (top 8)\nnone" }

    let updatesWidth = 4
    let nodesWidth = 5
    let ageWidth = 6
    let idWidth = max(10, width - updatesWidth - nodesWidth - ageWidth - 3)
    let lines = snapshot.widgets.map { widget in
      compactRow([
        column(widget.id, width: idWidth),
        column(String(widget.updatesTotal), width: updatesWidth, alignment: .right),
        column(String(widget.lastNodeCount), width: nodesWidth, alignment: .right),
        column(relative(widget.lastUpdatedAt), width: ageWidth, alignment: .right),
      ])
    }
    let header = compactRow([
      column("id", width: idWidth),
      column("upd", width: updatesWidth, alignment: .right),
      column("nodes", width: nodesWidth, alignment: .right),
      column("age", width: ageWidth, alignment: .right),
    ])
    return (["Widget trees (top 8)", header] + lines)
      .joined(separator: "\n")
  }

  /// Renders the highest-volume events using compact aligned columns.
  static func watchEvents(_ snapshot: IPC.MetricsSnapshot, width: Int) -> String {
    guard !snapshot.events.isEmpty else { return "Events (top 8)\nnone" }

    let totalWidth = 5
    let rateWidth = 6
    let droppedWidth = 4
    let coalescedWidth = 4
    let nameWidth = max(
      8,
      width - totalWidth - rateWidth - droppedWidth - coalescedWidth - 4
    )
    let lines = snapshot.events.map { event in
      compactRow([
        column(event.name, width: nameWidth),
        column(String(event.total), width: totalWidth, alignment: .right),
        column("\(number(event.perSecond))/s", width: rateWidth, alignment: .right),
        column(String(event.droppedTotal), width: droppedWidth, alignment: .right),
        column(String(event.coalescedTotal), width: coalescedWidth, alignment: .right),
      ])
    }
    let header = compactRow([
      column("name", width: nameWidth),
      column("tot", width: totalWidth, alignment: .right),
      column("rate", width: rateWidth, alignment: .right),
      column("drop", width: droppedWidth, alignment: .right),
      column("coal", width: coalescedWidth, alignment: .right),
    ])
    return (["Events (top 8)", header] + lines)
      .joined(separator: "\n")
  }

  /// Joins fixed-width columns with the single-space gaps used by compact tiles.
  static func compactRow(_ columns: [String]) -> String {
    columns.joined(separator: " ")
  }

  /// Joins multiline tiles horizontally, padding shorter tiles with blank lines.
  static func tileRow(_ tiles: [String], widths: [Int], gap: Int) -> String {
    guard tiles.count == widths.count else { return tiles.joined(separator: "\n\n") }

    let tileLines = tiles.map { $0.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) }
    let height = tileLines.map(\.count).max() ?? 0
    let separator = String(repeating: " ", count: max(1, gap))

    return (0..<height).map { lineIndex in
      zip(tileLines, widths).map { lines, width in
        column(lineIndex < lines.count ? lines[lineIndex] : "", width: width)
      }.joined(separator: separator)
    }.joined(separator: "\n")
  }

  /// Renders one aligned label/value line inside a compact tile.
  static func compactMetric(_ label: String, _ value: String, width: Int) -> String {
    let valueWidth = min(max(7, value.count), max(7, width / 2))
    let labelWidth = max(8, width - valueWidth - 2)
    return row([
      column(label, width: labelWidth),
      column(value, width: valueWidth, alignment: .right),
    ])
  }

  /// Renders watch-mode graph rows from recent metric history.
  static func graphs(_ snapshot: IPC.MetricsSnapshot, history: MetricsHistory) -> String {
    let lines = [
      row([
        column("metric", width: 10),
        column("now", width: 8, alignment: .right),
        column("avg", width: 8, alignment: .right),
        "history (\(watchGraphWidth))",
      ]),
      graphLine(
        label: "app cpu",
        current: percent(snapshot.process.cpuPercent),
        average: percent(average(history.values(for: "process.cpu"))),
        values: history.values(for: "process.cpu"),
        absoluteMax: 100,
        fixedWidth: watchGraphWidth
      ),
      graphLine(
        label: "lua cpu",
        current: percent(snapshot.lua.cpuPercent),
        average: percent(average(history.values(for: "lua.cpu"))),
        values: history.values(for: "lua.cpu"),
        absoluteMax: 100,
        fixedWidth: watchGraphWidth
      ),
      graphLine(
        label: "events/s",
        current: number(snapshot.runtime.eventsPerSecond),
        average: number(average(history.values(for: "runtime.events"))),
        values: history.values(for: "runtime.events"),
        fixedWidth: watchGraphWidth
      ),
      graphLine(
        label: "tree/s",
        current: number(snapshot.runtime.treeUpdatesPerSecond),
        average: number(average(history.values(for: "runtime.tree"))),
        values: history.values(for: "runtime.tree"),
        fixedWidth: watchGraphWidth
      ),
    ]

    return (["Graphs"] + lines).joined(separator: "\n")
  }
  /// Renders one graph table row.
  static func graphLine(
    label: String,
    current: String,
    average: String,
    values: [Double],
    absoluteMax: Double? = nil,
    fixedWidth: Int
  ) -> String {
    row([
      column(label, width: 10),
      column(current, width: 8, alignment: .right),
      column(average, width: 8, alignment: .right),
      sparkline(values, absoluteMax: absoluteMax, fixedWidth: fixedWidth),
    ])
  }

  /// Renders recent numeric values as a fixed-width sparkline.
  static func sparkline(
    _ values: [Double],
    absoluteMax: Double? = nil,
    fixedWidth: Int
  ) -> String {
    guard fixedWidth > 0 else { return "[]" }
    guard !values.isEmpty else { return "[" + String(repeating: " ", count: fixedWidth) + "]" }

    let symbols = Array("▁▂▃▄▅▆▇█")
    let visibleValues = values.suffix(fixedWidth).map { value in
      value.isFinite ? max(0, value) : 0
    }
    let finiteAbsoluteMax = absoluteMax.flatMap { value in
      value.isFinite && value > 0 ? value : nil
    }
    let maxValue = finiteAbsoluteMax ?? (visibleValues.max() ?? 0)
    let leadingPadding = max(0, fixedWidth - visibleValues.count)

    guard maxValue > 0 else {
      return "[" + String(repeating: " ", count: leadingPadding)
        + String(repeating: String(symbols[0]), count: visibleValues.count) + "]"
    }

    let rendered = visibleValues.map { value -> Character in
      let normalized = min(max(value / maxValue, 0), 1)
      let index = Int((normalized * Double(symbols.count - 1)).rounded())
      return symbols[index]
    }

    return "[" + String(repeating: " ", count: leadingPadding) + String(rendered) + "]"
  }
}
