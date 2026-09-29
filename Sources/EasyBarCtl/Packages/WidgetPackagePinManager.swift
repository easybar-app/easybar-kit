import EasyBarShared
import Foundation

/// Stores widget package pin manager data.
struct WidgetPackagePinManager {
  /// The packages directory for this widget package pin manager.
  private let packagesDirectory: URL
  /// The database store for this widget package pin manager.
  private let databaseStore: WidgetPackageDatabaseStore
  /// The pin store for this widget package pin manager.
  private let pinStore: WidgetPackagePinStore

  /// Creates a widget package pin manager.
  init(
    fileManager: FileManager = .default,
    packagesDirectory: URL = SharedPathDefaults.defaultWidgetPackagesPath()
  ) {
    self.packagesDirectory = packagesDirectory
    databaseStore = WidgetPackageDatabaseStore(fileManager: fileManager)
    pinStore = WidgetPackagePinStore(fileManager: fileManager)
  }

  /// Pins the selected package.
  func pin(name: String) throws -> InstalledWidgetPackage {
    let package = try installedPackage(named: name)
    var pins = try pinStore.load(from: packagesDirectory)
    guard pins.insert(name).inserted else {
      throw WidgetPackageError.packageAlreadyPinned(name)
    }
    try pinStore.write(pins, to: packagesDirectory)
    return package
  }

  /// Unpins the selected package.
  func unpin(name: String) throws -> InstalledWidgetPackage {
    let package = try installedPackage(named: name)
    var pins = try pinStore.load(from: packagesDirectory)
    guard pins.remove(name) != nil else {
      throw WidgetPackageError.packageNotPinned(name)
    }
    try pinStore.write(pins, to: packagesDirectory)
    return package
  }

  /// Returns the installed package.
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

/// Pins the selected widget package.
func pinWidgetPackage(name: String, context: AppContext) throws {
  do {
    context.debug("pinning widget package \(name)")
    let package = try WidgetPackagePinManager().pin(name: name)
    fputs("Pinned \(package.name) \(package.version) (\(package.kind.rawValue))\n", stdout)
  } catch {
    throw AppError.commandFailed(error.localizedDescription)
  }
}

/// Unpins the selected widget package.
func unpinWidgetPackage(name: String, context: AppContext) throws {
  do {
    context.debug("unpinning widget package \(name)")
    let package = try WidgetPackagePinManager().unpin(name: name)
    fputs("Unpinned \(package.name) \(package.version) (\(package.kind.rawValue))\n", stdout)
  } catch {
    throw AppError.commandFailed(error.localizedDescription)
  }
}
