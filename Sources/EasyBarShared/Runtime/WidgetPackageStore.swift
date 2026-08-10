import Foundation

/// Filesystem layout for managed Lua widget packages.
public enum WidgetPackageStore {
  public static let layoutVersion = 3

  /// Returns the directory containing activated widget projections and exported modules.
  public static func activeDirectory(in packagesDirectory: URL) -> URL {
    packagesDirectory.appending(path: "active", directoryHint: .isDirectory)
  }

  /// Returns the directory containing versioned package installations.
  public static func storeDirectory(in packagesDirectory: URL) -> URL {
    packagesDirectory.appending(path: "store", directoryHint: .isDirectory)
  }
}
