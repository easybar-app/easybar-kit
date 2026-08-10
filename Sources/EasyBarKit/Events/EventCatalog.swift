import EasyBarShared
import Foundation

/// Shared event-name catalog and Lua parity checks.
enum EventCatalog {
  /// Synthetic event name used to force widget refreshes.
  static let forcedEventName = "forced"
  /// App events that are not exposed as Lua event tokens.
  private static let internalAppEventNames: Set<String> = [
    AppEvent.manualRefresh.rawValue,
    AppEvent.intervalTick.rawValue,
  ]

  /// Event names exposed to Lua widget token matching.
  static let luaTokenEventNames: Set<String> = Set(AppEvent.allCases.map(\.rawValue))
    .subtracting(internalAppEventNames)
    .union(Set(WidgetEvent.allCases.map(\.rawValue)))
    .union([forcedEventName])

  /// App event names that Lua can subscribe to as drivers.
  static let luaDriverEventNames: Set<String> = Set(AppEvent.allCases.map(\.rawValue))
    .subtracting(internalAppEventNames)
    .union([forcedEventName])

  /// Verifies that the Lua token file matches the Swift event catalog.
  static func validateLuaDefinitions(logger: ProcessLogger) {
    let warnings = currentLuaDefinitionWarnings()

    guard !warnings.isEmpty else { return }

    for warning in warnings {
      logger.warn(warning)
    }
  }

  /// Returns human-readable mismatch warnings for the Lua token definitions.
  static func currentLuaDefinitionWarnings() -> [String] {
    guard let catalog = loadGeneratedCatalog() else {
      return [
        "unable to validate generated event catalog parity because Events/event_catalog.json could not be loaded"
      ]
    }

    var warnings: [String] = []

    appendMismatchWarnings(
      label: "generated lua event tokens",
      expected: luaTokenEventNames,
      actual: catalog.luaTokenNames,
      warnings: &warnings
    )

    appendMismatchWarnings(
      label: "generated lua driver events",
      expected: luaDriverEventNames,
      actual: catalog.luaDriverNames,
      warnings: &warnings
    )

    appendMismatchWarnings(
      label: "generated mouse buttons",
      expected: Set(MouseButton.allCases.map(\.rawValue)),
      actual: catalog.mouseButtons,
      warnings: &warnings
    )

    appendMismatchWarnings(
      label: "generated scroll directions",
      expected: Set(ScrollDirection.allCases.map(\.rawValue)),
      actual: catalog.scrollDirections,
      warnings: &warnings
    )

    return warnings
  }

  /// Loads the bundled generated event catalog manifest.
  private static func loadGeneratedCatalog() -> GeneratedCatalog? {
    let candidateURLs = [
      AppResourceLocator.url(
        forResource: "event_catalog",
        withExtension: "json",
        subdirectory: "Events"
      ),
      URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("event_catalog.json"),
      URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Sources/EasyBarKit/Events/event_catalog.json"),
    ].compactMap { $0 }

    guard
      let url = candidateURLs.first(where: { (try? $0.checkResourceIsReachable()) == true }),
      let data = try? Data(contentsOf: url),
      let catalog = try? JSONDecoder().decode(GeneratedCatalogManifest.self, from: data)
    else {
      return nil
    }

    let tokenNames = Set(
      [catalog.forcedEvent.runtimeName]
        + catalog.appEvents.map(\.runtimeName)
        + catalog.widgetGroups.flatMap(\.events).map(\.runtimeName)
    )

    let driverNames = Set(
      [catalog.forcedEvent.runtimeName]
        + catalog.appEvents.filter(\.driver).map(\.runtimeName)
    )

    return GeneratedCatalog(
      luaTokenNames: tokenNames,
      luaDriverNames: driverNames,
      mouseButtons: Set(catalog.mouseButtons.map(\.value)),
      scrollDirections: Set(catalog.scrollDirections.map(\.value))
    )
  }

  /// Appends missing and unexpected event-name warnings for one Lua definition set.
  private static func appendMismatchWarnings(
    label: String,
    expected: Set<String>,
    actual: Set<String>,
    warnings: inout [String]
  ) {
    let missing = expected.subtracting(actual).sorted()
    let unexpected = actual.subtracting(expected).sorted()

    if !missing.isEmpty {
      warnings.append("\(label) missing Swift-defined names: \(missing.joined(separator: ", "))")
    }

    if !unexpected.isEmpty {
      warnings.append(
        "\(label) contain names missing from Swift: \(unexpected.joined(separator: ", "))"
      )
    }
  }
}

/// Decoded event-name sets from the generated catalog.
private struct GeneratedCatalog {
  /// Generated Lua token event names.
  let luaTokenNames: Set<String>
  /// Generated Lua driver event names.
  let luaDriverNames: Set<String>
  /// Generated mouse button names.
  let mouseButtons: Set<String>
  /// Generated scroll direction names.
  let scrollDirections: Set<String>
}

/// Bundle manifest produced by the event catalog generator.
private struct GeneratedCatalogManifest: Decodable {
  /// Generated forced event entry.
  let forcedEvent: GeneratedCatalogEvent
  /// Generated app event entries.
  let appEvents: [GeneratedCatalogEvent]
  /// Generated widget event groups.
  let widgetGroups: [GeneratedCatalogWidgetGroup]
  /// Generated mouse button names.
  let mouseButtons: [GeneratedCatalogValue]
  /// Generated scroll direction names.
  let scrollDirections: [GeneratedCatalogValue]
}

/// Generated widget event group.
private struct GeneratedCatalogWidgetGroup: Decodable {
  /// Events in this widget group.
  let events: [GeneratedCatalogEvent]
}

/// Generated event entry.
private struct GeneratedCatalogEvent: Decodable {
  /// Runtime event name.
  let runtimeName: String
  /// Whether Lua may subscribe to this app event as a driver.
  let driver: Bool

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    runtimeName = try container.decode(String.self, forKey: .runtimeName)
    driver = try container.decodeIfPresent(Bool.self, forKey: .driver) ?? false
  }

  private enum CodingKeys: String, CodingKey {
    case runtimeName
    case driver
  }
}

/// Generated manifest value entry.
private struct GeneratedCatalogValue: Decodable {
  /// Raw catalog value.
  let value: String
}
