import EasyBarShared
import Foundation

/// Stores installed widget package status data.
struct InstalledWidgetPackageStatus: Codable, Equatable {
  /// The name for this installed widget package status.
  let name: String
  /// The version for this installed widget package status.
  let version: String
  /// The kind for this installed widget package status.
  let kind: WidgetPackageKind
  /// The entrypoint for this installed widget package status.
  let entrypoint: String?
  /// The dependencies for this installed widget package status.
  let dependencies: [String: String]
  /// The exports for this installed widget package status.
  let exports: [String: String]
  /// The source for this installed widget package status.
  let source: String
  /// Whether this installed widget package status is pinned.
  let pinned: Bool

  /// Creates an installed widget package status.
  init(package: InstalledWidgetPackage, pinned: Bool) {
    name = package.name
    version = package.version
    kind = package.kind
    entrypoint = package.entrypoint
    dependencies = package.dependencies
    exports = package.exports
    source = package.source
    self.pinned = pinned
  }
}

/// Stores widget package lister data.
struct WidgetPackageLister {
  /// The packages directory for this widget package lister.
  private let packagesDirectory: URL
  /// The database store for this widget package lister.
  private let databaseStore: WidgetPackageDatabaseStore
  /// The pin store for this widget package lister.
  private let pinStore: WidgetPackagePinStore

  /// Creates a widget package lister.
  init(
    fileManager: FileManager = .default,
    packagesDirectory: URL = SharedPathDefaults.defaultWidgetPackagesPath()
  ) {
    self.packagesDirectory = packagesDirectory
    databaseStore = WidgetPackageDatabaseStore(fileManager: fileManager)
    pinStore = WidgetPackagePinStore(fileManager: fileManager)
  }

  /// Returns the installed.
  func installed(filter: InstalledWidgetPackageFilter) throws -> [InstalledWidgetPackageStatus] {
    let packages = try databaseStore.load(from: packagesDirectory).packages
    let pins = try pinStore.load(from: packagesDirectory)
    return packages.filter { package in
      switch filter {
      case .all: true
      case .widgets: package.kind == .widget
      case .libraries: package.kind == .library
      }
    }.map { package in
      InstalledWidgetPackageStatus(package: package, pinned: pins.contains(package.name))
    }.sorted { left, right in
      if left.kind != right.kind { return left.kind == .widget }
      return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
    }
  }
}

/// Lists installed widget packages.
func listInstalledWidgetPackages(
  options: InstalledWidgetPackageOptions,
  context: AppContext
) throws {
  do {
    context.debug("listing installed widget packages")
    let packages = try WidgetPackageLister().installed(filter: options.filter)
    try CLIOutput.printInstalledWidgetPackages(packages, json: options.json)
  } catch let error as AppError {
    throw error
  } catch {
    throw AppError.commandFailed(error.localizedDescription)
  }
}
