import EasyBarShared
import Foundation

/// Stores widget package pin manager data.
struct WidgetPackagePinManager {
  /// The packages directory for this widget package pin manager.
  private let packagesDirectory: URL
  /// The file manager used when acquiring the shared package lock.
  private let fileManager: FileManager
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
    self.fileManager = fileManager
    databaseStore = WidgetPackageDatabaseStore(fileManager: fileManager)
    pinStore = WidgetPackagePinStore(fileManager: fileManager)
  }

  /// Pins the selected package.
  func pin(name: String) throws -> InstalledWidgetPackage {
    try WidgetPackageOperationLock.withExclusiveAccess(
      to: packagesDirectory,
      fileManager: fileManager
    ) {
      try changePin(name: name, shouldPin: true)
    }
  }

  /// Unpins one package while other CLI mutations are excluded.
  func unpin(name: String) throws -> InstalledWidgetPackage {
    try WidgetPackageOperationLock.withExclusiveAccess(
      to: packagesDirectory,
      fileManager: fileManager
    ) {
      try changePin(name: name, shouldPin: false)
    }
  }

  /// Updates the package pin set using the database read from the same locked operation.
  private func changePin(name: String, shouldPin: Bool) throws -> InstalledWidgetPackage {
    let package = try installedPackage(named: name)
    var pins = try pinStore.load(from: packagesDirectory)
    if shouldPin {
      guard pins.insert(name).inserted else {
        throw WidgetPackageError.packageAlreadyPinned(name)
      }
    } else {
      guard pins.remove(name) != nil else {
        throw WidgetPackageError.packageNotPinned(name)
      }
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
