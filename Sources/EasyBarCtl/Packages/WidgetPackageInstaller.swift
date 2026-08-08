import EasyBarShared
import Foundation

final class WidgetPackageInstaller {
  private let logger: ProcessLogger
  private let fileManager: FileManager
  private let packagesDirectory: URL
  private let legacyWidgetsDirectory: URL?

  init(
    logger: ProcessLogger,
    fileManager: FileManager = .default,
    packagesDirectory: URL = SharedPathDefaults.defaultWidgetPackagesPath(),
    legacyWidgetsDirectory: URL? = nil
  ) {
    self.logger = logger
    self.fileManager = fileManager
    self.packagesDirectory = packagesDirectory
    self.legacyWidgetsDirectory = legacyWidgetsDirectory
  }

  func install(options: WidgetPackageInstallOptions) async throws -> [InstalledWidgetPackage] {
    let legacyWidgetsDirectory = try resolvedLegacyWidgetsDirectory()
    try WidgetPackageStore.migrateLegacyInstallation(
      from: legacyWidgetsDirectory,
      to: packagesDirectory,
      fileManager: fileManager
    )
    try fileManager.createDirectory(at: packagesDirectory, withIntermediateDirectories: true)
    let databaseURL = packagesDirectory.appending(path: "installed.json")
    let database = try loadDatabase(at: databaseURL)

    let temporaryDirectory = fileManager.temporaryDirectory.appending(
      path: "easybar-package-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: temporaryDirectory) }

    let resolver = WidgetPackageResolver(
      registrySource: options.registry,
      useRegistry: options.useRegistry,
      temporaryDirectory: temporaryDirectory.appending(path: "downloads", directoryHint: .isDirectory),
      installed: database.packages,
      logger: logger
    )
    try fileManager.createDirectory(
      at: temporaryDirectory.appending(path: "downloads", directoryHint: .isDirectory),
      withIntermediateDirectories: true
    )
    let packages = try await resolver.resolve(source: options.source, sha256: options.sha256)
    let materializer = WidgetPackageMaterializer(fileManager: fileManager)
    return try materializer.install(
      packages,
      into: packagesDirectory,
      database: database,
      stagingDirectory: temporaryDirectory.appending(path: "install", directoryHint: .isDirectory)
    )
  }

  private func resolvedLegacyWidgetsDirectory() throws -> URL {
    if let legacyWidgetsDirectory {
      return legacyWidgetsDirectory
    }
    do {
      return URL(fileURLWithPath: try SharedRuntimeConfig.load().app.widgetsPath, isDirectory: true)
    } catch {
      throw WidgetPackageError.invalidSource(
        "could not resolve widgets_dir for package migration: \(error.localizedDescription)"
      )
    }
  }

  private func loadDatabase(at url: URL) throws -> InstalledWidgetPackages {
    guard fileManager.fileExists(atPath: url.path) else { return .empty }
    let decoded: InstalledWidgetPackages
    do {
      decoded = try JSONDecoder().decode(
        InstalledWidgetPackages.self,
        from: Data(contentsOf: url)
      )
    } catch {
      throw WidgetPackageError.installConflict(
        "could not read package database at \(url.path): \(error.localizedDescription)"
      )
    }
    guard decoded.layoutVersion == WidgetPackageStore.layoutVersion else {
      throw WidgetPackageError.installConflict("unsupported installed package layout")
    }
    guard Set(decoded.packages.map(\.name)).count == decoded.packages.count else {
      throw WidgetPackageError.installConflict("installed package database contains duplicate names")
    }
    var exportedModules: Set<String> = []
    for package in decoded.packages {
      for module in package.exports.keys {
        guard exportedModules.insert(module).inserted else {
          throw WidgetPackageError.installConflict(
            "installed package database contains duplicate export '\(module)'"
          )
        }
      }
    }
    return decoded
  }
}

func installWidgetPackage(
  options: WidgetPackageInstallOptions,
  context: AppContext
) async throws {
  do {
    let installed = try await WidgetPackageInstaller(logger: context.logger).install(options: options)
    for package in installed {
      fputs("Installed \(package.name) \(package.version) (\(package.kind.rawValue))\n", stdout)
    }
    fputs("Reload EasyBar with: easybar config reload\n", stdout)
  } catch {
    throw AppError.commandFailed(error.localizedDescription)
  }
}
