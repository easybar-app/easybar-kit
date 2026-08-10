import EasyBarShared
import Foundation

final class WidgetPackageUninstaller {
  private let fileManager: FileManager
  private let packagesDirectory: URL

  init(
    fileManager: FileManager = .default,
    packagesDirectory: URL = SharedPathDefaults.defaultWidgetPackagesPath()
  ) {
    self.fileManager = fileManager
    self.packagesDirectory = packagesDirectory
  }

  func uninstall(name: String) throws -> InstalledWidgetPackage {
    guard WidgetPackageManifestParser.isPackageName(name) else {
      throw WidgetPackageError.invalidSource("invalid package name '\(name)'")
    }

    let databaseStore = WidgetPackageDatabaseStore(fileManager: fileManager)
    var database = try databaseStore.load(from: packagesDirectory)
    guard let package = database.packages.first(where: { $0.name == name }) else {
      throw WidgetPackageError.packageNotInstalled(name)
    }
    let dependents = database.packages
      .filter { $0.name != name && $0.dependencies[name] != nil }
      .map(\.name)
      .sorted()
    guard dependents.isEmpty else {
      throw WidgetPackageError.packageRequired(name: name, dependents: dependents)
    }

    try fileManager.createDirectory(at: packagesDirectory, withIntermediateDirectories: true)
    let stagingDirectory = packagesDirectory.appending(
      path: ".uninstall-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)

    let activeDirectory = WidgetPackageStore.activeDirectory(in: packagesDirectory)
    let storeDirectory = WidgetPackageStore.storeDirectory(in: packagesDirectory)
    var moves: [(original: URL, staged: URL)] = []

    func stage(_ original: URL, at relativePath: String) throws {
      guard itemExists(original) else { return }
      let staged = stagingDirectory.appending(path: relativePath)
      try fileManager.createDirectory(
        at: staged.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try fileManager.moveItem(at: original, to: staged)
      moves.append((original, staged))
    }

    do {
      if package.kind == .widget {
        try stage(
          activeDirectory.appending(path: package.name, directoryHint: .isDirectory),
          at: "active/\(package.name)"
        )
      }
      for module in package.exports.keys {
        try stage(
          moduleURL(module, in: activeDirectory),
          at: "active/shared/\(module.replacing(".", with: "/")).lua"
        )
      }
      try stage(
        storeDirectory.appending(path: package.name, directoryHint: .isDirectory),
        at: "store/\(package.name)"
      )

      database.packages.removeAll { $0.name == name }
      try databaseStore.write(database, to: packagesDirectory)
    } catch {
      var restorationFailure: Error?
      for move in moves.reversed() where itemExists(move.staged) {
        do {
          try fileManager.createDirectory(
            at: move.original.deletingLastPathComponent(),
            withIntermediateDirectories: true
          )
          try fileManager.moveItem(at: move.staged, to: move.original)
        } catch {
          restorationFailure = error
        }
      }
      if let restorationFailure {
        throw WidgetPackageError.installConflict(
          "uninstall failed and recovery files remain at \(stagingDirectory.path): "
            + restorationFailure.localizedDescription
        )
      }
      try? fileManager.removeItem(at: stagingDirectory)
      throw error
    }

    try? fileManager.removeItem(at: stagingDirectory)
    return package
  }

  private func moduleURL(_ module: String, in root: URL) -> URL {
    root.appending(path: "shared/\(module.replacing(".", with: "/")).lua")
  }

  private func itemExists(_ url: URL) -> Bool {
    fileManager.fileExists(atPath: url.path)
      || (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) != nil
  }
}

func uninstallWidgetPackage(name: String, context: AppContext) throws {
  do {
    context.debug("uninstalling widget package \(name)")
    let package = try WidgetPackageUninstaller().uninstall(name: name)
    fputs("Uninstalled \(package.name) \(package.version) (\(package.kind.rawValue))\n", stdout)
    fputs("Reload EasyBar with: easybar config reload\n", stdout)
  } catch {
    throw AppError.commandFailed(error.localizedDescription)
  }
}
