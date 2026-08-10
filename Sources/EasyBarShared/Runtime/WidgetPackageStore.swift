import Foundation

/// Filesystem layout for managed Lua widget packages.
public enum WidgetPackageStore {
  public static let layoutVersion = 5

  /// Returns the directory containing active widget entrypoints and exported modules.
  public static func activeDirectory(in packagesDirectory: URL) -> URL {
    packagesDirectory.appending(path: "active", directoryHint: .isDirectory)
  }

  /// Returns the directory containing committed versioned package installations.
  public static func storeDirectory(in packagesDirectory: URL) -> URL {
    packagesDirectory.appending(path: "store", directoryHint: .isDirectory)
  }
}
