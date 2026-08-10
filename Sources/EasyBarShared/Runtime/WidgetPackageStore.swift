import Foundation

/// Filesystem layout for managed Lua widget packages.
public enum WidgetPackageStore {
  public static let layoutVersion = 4

  /// Returns the directory containing active widget and library projections.
  public static func activeDirectory(in packagesDirectory: URL) -> URL {
    packagesDirectory.appending(path: "active", directoryHint: .isDirectory)
  }

  /// Returns the directory containing immutable versioned package installations.
  public static func storeDirectory(in packagesDirectory: URL) -> URL {
    packagesDirectory.appending(path: "store", directoryHint: .isDirectory)
  }

  /// Returns the exact validated package source stored for one version.
  public static func sourceDirectory(in versionDirectory: URL) -> URL {
    versionDirectory.appending(path: "source", directoryHint: .isDirectory)
  }

  /// Returns the generated runtime projection stored for one version.
  public static func runtimeDirectory(in versionDirectory: URL) -> URL {
    versionDirectory.appending(path: "runtime", directoryHint: .isDirectory)
  }
}
