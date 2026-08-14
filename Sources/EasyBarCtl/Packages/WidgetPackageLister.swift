import EasyBarShared
import Foundation

struct InstalledWidgetPackageStatus: Codable, Equatable {
  let name: String
  let version: String
  let kind: WidgetPackageKind
  let entrypoint: String?
  let dependencies: [String: String]
  let exports: [String: String]
  let source: String
  let pinned: Bool

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

struct WidgetPackageLister {
  private let packagesDirectory: URL
  private let databaseStore: WidgetPackageDatabaseStore
  private let pinStore: WidgetPackagePinStore

  init(
    fileManager: FileManager = .default,
    packagesDirectory: URL = SharedPathDefaults.defaultWidgetPackagesPath()
  ) {
    self.packagesDirectory = packagesDirectory
    databaseStore = WidgetPackageDatabaseStore(fileManager: fileManager)
    pinStore = WidgetPackagePinStore(fileManager: fileManager)
  }

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
