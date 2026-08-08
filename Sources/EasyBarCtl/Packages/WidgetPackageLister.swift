import EasyBarShared
import Foundation

struct WidgetPackageLister {
  private let packagesDirectory: URL
  private let databaseStore: WidgetPackageDatabaseStore

  init(
    fileManager: FileManager = .default,
    packagesDirectory: URL = SharedPathDefaults.defaultWidgetPackagesPath()
  ) {
    self.packagesDirectory = packagesDirectory
    databaseStore = WidgetPackageDatabaseStore(fileManager: fileManager)
  }

  func installed(filter: InstalledWidgetPackageFilter) throws -> [InstalledWidgetPackage] {
    let packages = try databaseStore.load(from: packagesDirectory).packages
    return packages.filter { package in
      switch filter {
      case .all: true
      case .widgets: package.kind == .widget
      case .libraries: package.kind == .library
      }
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
