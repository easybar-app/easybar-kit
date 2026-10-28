import EasyBarShared
import Foundation

/// Validates and persists the installed-package database as atomic JSON.
struct WidgetPackageDatabaseStore {
  /// The file manager used for filesystem operations.
  private let fileManager: FileManager

  /// Creates a database store with an injectable filesystem implementation.
  init(fileManager: FileManager = .default) {
    self.fileManager = fileManager
  }

  /// Loads installed packages and rejects invalid layouts, duplicate names, and export collisions.
  func load(from packagesDirectory: URL) throws -> InstalledWidgetPackages {
    let url = packagesDirectory.appending(path: "installed.json")
    guard fileManager.fileExists(atPath: url.path) else { return .empty }
    let database: InstalledWidgetPackages
    do {
      database = try JSONDecoder().decode(
        InstalledWidgetPackages.self,
        from: Data(contentsOf: url)
      )
    } catch {
      throw WidgetPackageError.installConflict(
        "could not read package database at \(url.path): \(error.localizedDescription)"
      )
    }
    guard database.layoutVersion == WidgetPackageStore.layoutVersion else {
      throw WidgetPackageError.installConflict("unsupported installed package layout")
    }
    guard Set(database.packages.map(\.name)).count == database.packages.count else {
      throw WidgetPackageError.installConflict("installed package database contains duplicate names")
    }

    var exportedModules: Set<String> = []
    for package in database.packages {
      guard WidgetPackageManifestParser.isPackageName(package.name) else {
        throw WidgetPackageError.installConflict(
          "installed package database contains invalid name '\(package.name)'"
        )
      }
      for module in package.exports.keys {
        guard WidgetPackageManifestParser.isModuleName(module) else {
          throw WidgetPackageError.installConflict(
            "installed package database contains invalid export '\(module)'"
          )
        }
        guard exportedModules.insert(module).inserted else {
          throw WidgetPackageError.installConflict(
            "installed package database contains duplicate export '\(module)'"
          )
        }
      }
    }
    return database
  }

  /// Atomically writes package metadata with stable ordering and a trailing newline.
  func write(_ database: InstalledWidgetPackages, to packagesDirectory: URL) throws {
    let url = packagesDirectory.appending(path: "installed.json")
    try fileManager.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    var data = try encoder.encode(database)
    data.append(0x0A)
    try data.write(to: url, options: .atomic)
  }

}
