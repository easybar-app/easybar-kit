import EasyBarShared
import Foundation

struct WidgetPackagePinManager {
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

  func pin(name: String) throws -> InstalledWidgetPackage {
    let package = try installedPackage(named: name)
    var pins = try pinStore.load(from: packagesDirectory)
    guard pins.insert(name).inserted else {
      throw WidgetPackageError.packageAlreadyPinned(name)
    }
    try pinStore.write(pins, to: packagesDirectory)
    return package
  }

  func unpin(name: String) throws -> InstalledWidgetPackage {
    let package = try installedPackage(named: name)
    var pins = try pinStore.load(from: packagesDirectory)
    guard pins.remove(name) != nil else {
      throw WidgetPackageError.packageNotPinned(name)
    }
    try pinStore.write(pins, to: packagesDirectory)
    return package
  }

  private func installedPackage(named name: String) throws -> InstalledWidgetPackage {
    guard WidgetPackageManifestParser.isPackageName(name) else {
      throw WidgetPackageError.invalidSource("invalid package name '\(name)'")
    }
    let database = try databaseStore.load(from: packagesDirectory)
    guard let package = database.packages.first(where: { $0.name == name }) else {
      throw WidgetPackageError.packageNotInstalled(name)
    }
    return package
  }
}

func pinWidgetPackage(name: String, context: AppContext) throws {
  do {
    context.debug("pinning widget package \(name)")
    let package = try WidgetPackagePinManager().pin(name: name)
    fputs("Pinned \(package.name) \(package.version) (\(package.kind.rawValue))\n", stdout)
  } catch {
    throw AppError.commandFailed(error.localizedDescription)
  }
}

func unpinWidgetPackage(name: String, context: AppContext) throws {
  do {
    context.debug("unpinning widget package \(name)")
    let package = try WidgetPackagePinManager().unpin(name: name)
    fputs("Unpinned \(package.name) \(package.version) (\(package.kind.rawValue))\n", stdout)
  } catch {
    throw AppError.commandFailed(error.localizedDescription)
  }
}
