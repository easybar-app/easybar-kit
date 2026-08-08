import EasyBarShared
import Foundation

struct WidgetPackageDatabaseStore {
  private let fileManager: FileManager

  init(fileManager: FileManager = .default) {
    self.fileManager = fileManager
  }

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
        guard Self.isModuleName(module) else {
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

  private static func isModuleName(_ value: String) -> Bool {
    value.range(
      of: #"^[A-Za-z_][A-Za-z0-9_-]*(?:\.[A-Za-z_][A-Za-z0-9_-]*)*$"#,
      options: .regularExpression
    ) != nil
  }
}
