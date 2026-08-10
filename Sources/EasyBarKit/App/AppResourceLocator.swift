import Foundation

/// Resolves EasyBar app resources without relying on SwiftPM's generated Bundle.module accessor.
///
/// Packaged app bundles stage resources under `Contents/Resources/EasyBar`:
///
/// - `Lua/runtime.lua`
/// - `Lua/easybar_api.lua`
/// - `Lua/easybar/...`
/// - `Events/event_catalog.json`
/// - `ThemeTokens/theme_tokens.json`
///
/// Source-tree fallbacks are kept so tests and local development continue to work before
/// resources are staged into an app bundle.
enum AppResourceLocator {
  /// Name of the app-owned resource directory inside `Contents/Resources`.
  private static let appResourceDirectoryName = "EasyBar"
  /// Resource names that live outside the Lua tree in packaged app resources.
  private static let packagedResourceSubdirectories = [
    "event_catalog": "Events",
    "theme_tokens": "ThemeTokens",
  ]
  /// Resource names that live outside the Lua tree in source-tree resources.
  private static let sourceResourceSubdirectories = [
    "event_catalog": "Events",
    "theme_tokens": "Theme",
  ]

  /// Supported resource layouts used by candidate URL generation.
  private enum ResourceLayout {
    case packaged
    case source
  }

  /// Returns one bundled resource URL from packaged or source-tree locations.
  static func url(
    forResource name: String,
    withExtension fileExtension: String,
    subdirectory: String? = nil
  ) -> URL? {
    let fileManager = FileManager.default

    for candidate in resourceCandidates(
      forResource: name,
      withExtension: fileExtension,
      subdirectory: subdirectory
    ) {
      if fileManager.fileExists(atPath: candidate.path) {
        return candidate
      }
    }

    return nil
  }

  /// Returns candidate URLs for one resource in the order they should be preferred.
  static func resourceCandidates(
    forResource name: String,
    withExtension fileExtension: String,
    subdirectory: String?
  ) -> [URL] {
    let fileName = "\(name).\(fileExtension)"
    var candidates: [URL] = []

    for root in packagedResourceRoots() {
      candidates.append(
        root
          .appendingOptionalSubdirectory(
            mappedSubdirectory(
              for: .packaged,
              resource: name,
              fileExtension: fileExtension,
              requested: subdirectory
            )
          )
          .appendingPathComponent(fileName)
      )
    }

    for root in sourceRoots() {
      candidates.append(
        root
          .appendingOptionalSubdirectory(
            mappedSubdirectory(
              for: .source,
              resource: name,
              fileExtension: fileExtension,
              requested: subdirectory
            )
          )
          .appendingPathComponent(fileName)
      )
    }

    return unique(candidates)
  }

  /// Returns packaged app resource roots.
  private static func packagedResourceRoots() -> [URL] {
    var roots: [URL] = []

    if let resourceURL = Bundle.main.resourceURL {
      roots.append(resourceURL.appendingPathComponent(appResourceDirectoryName, isDirectory: true))
    }

    if let executableURL = Bundle.main.executableURL {
      roots.append(
        executableURL
          .deletingLastPathComponent()
          .deletingLastPathComponent()
          .appendingPathComponent("Resources", isDirectory: true)
          .appendingPathComponent(appResourceDirectoryName, isDirectory: true)
      )
    }

    return unique(roots)
  }

  /// Returns source-tree roots used by tests and direct local development runs.
  private static func sourceRoots() -> [URL] {
    let fileURL = URL(fileURLWithPath: #filePath)
    let sourceRoot =
      fileURL
      .deletingLastPathComponent()
      .deletingLastPathComponent()

    return unique([
      sourceRoot,
      URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Sources", isDirectory: true)
        .appendingPathComponent("EasyBarKit", isDirectory: true),
    ])
  }

  /// Maps logical resource requests to one concrete resource-layout subdirectory.
  private static func mappedSubdirectory(
    for layout: ResourceLayout,
    resource name: String,
    fileExtension: String,
    requested subdirectory: String?
  ) -> String? {
    if let subdirectory, !subdirectory.isEmpty {
      return requestedSubdirectory(subdirectory, for: layout)
    }

    if fileExtension == "lua" {
      return "Lua"
    }

    switch layout {
    case .packaged:
      return packagedResourceSubdirectories[name]
    case .source:
      return sourceResourceSubdirectories[name]
    }
  }

  /// Maps one caller-provided logical subdirectory to the target resource layout.
  private static func requestedSubdirectory(_ subdirectory: String, for layout: ResourceLayout)
    -> String
  {
    switch layout {
    case .packaged:
      return packagedRequestedSubdirectory(subdirectory)
    case .source:
      return sourceRequestedSubdirectory(subdirectory)
    }
  }

  /// Maps one caller-provided subdirectory to the packaged app resource layout.
  private static func packagedRequestedSubdirectory(_ subdirectory: String) -> String {
    switch subdirectory {
    case "Assets":
      return "Assets"
    case "Events":
      return "Events"
    case "Theme", "ThemeTokens":
      return "ThemeTokens"
    case "Lua":
      return "Lua"
    default:
      return subdirectory.hasPrefix("Lua/") ? subdirectory : "Lua/\(subdirectory)"
    }
  }

  /// Maps one caller-provided subdirectory to the source-tree resource layout.
  private static func sourceRequestedSubdirectory(_ subdirectory: String) -> String {
    switch subdirectory {
    case "Assets":
      return "Assets"
    case "Events":
      return "Events"
    case "Theme", "ThemeTokens":
      return "Theme"
    case "Lua":
      return "Lua"
    default:
      return subdirectory.hasPrefix("Lua/") ? subdirectory : "Lua/\(subdirectory)"
    }
  }

  /// Returns URLs without duplicate standardized paths.
  private static func unique(_ urls: [URL]) -> [URL] {
    var seen: Set<String> = []
    var result: [URL] = []

    for url in urls {
      let path = url.standardizedFileURL.path
      guard !seen.contains(path) else { continue }
      seen.insert(path)
      result.append(url)
    }

    return result
  }
}

extension URL {
  /// Appends one slash-separated optional subdirectory when present.
  fileprivate func appendingOptionalSubdirectory(_ subdirectory: String?) -> URL {
    guard let subdirectory, !subdirectory.isEmpty else { return self }

    var result = self
    for component in subdirectory.split(separator: "/") {
      result = result.appendingPathComponent(String(component), isDirectory: true)
    }
    return result
  }
}
