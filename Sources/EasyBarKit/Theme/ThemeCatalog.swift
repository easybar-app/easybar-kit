import EasyBarShared
import Foundation

/// Discovers bundled and user-provided themes available for session preview.
enum ThemeCatalog {
  /// Returns normalized theme names in stable display order.
  static func availableThemeNames(
    for snapshot: ConfigSnapshot,
    logger: ProcessLogger
  ) -> [String] {
    var directories: [URL] = []

    let userDirectory = NSString(string: snapshot.theme.themesDir).expandingTildeInPath
    if !userDirectory.isEmpty {
      directories.append(URL(fileURLWithPath: userDirectory, isDirectory: true))
    }
    if let resourceURL = Bundle.main.resourceURL {
      directories.append(resourceURL.appendingPathComponent("Themes", isDirectory: true))
    }
    if let executableURL = Bundle.main.executableURL {
      directories.append(
        executableURL.deletingLastPathComponent()
          .deletingLastPathComponent()
          .appendingPathComponent("Resources/Themes", isDirectory: true)
      )
    }
    directories.append(
      URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("themes", isDirectory: true)
    )

    var names: Set<String> = [snapshot.theme.name]
    let fileManager = FileManager.default
    var seenDirectories = Set<String>()
    for directory in directories {
      let directory = directory.standardizedFileURL
      guard seenDirectories.insert(directory.path).inserted else { continue }
      guard fileManager.fileExists(atPath: directory.path) else { continue }

      let urls: [URL]
      do {
        urls = try fileManager.contentsOfDirectory(
          at: directory,
          includingPropertiesForKeys: nil,
          options: [.skipsHiddenFiles]
        )
      } catch {
        logger.warn(
          "failed to discover themes",
          .field("directory", directory.path),
          .field("error", error)
        )
        continue
      }

      for url in urls where url.pathExtension.lowercased() == "toml" {
        names.insert(url.deletingPathExtension().lastPathComponent.lowercased())
      }
    }

    return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
  }
}
