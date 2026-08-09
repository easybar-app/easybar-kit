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
    let database = try WidgetPackageDatabaseStore(fileManager: fileManager).load(
      from: packagesDirectory
    )
    let namedInstalledPackage = installedPackageNamedBySource(
      options.source,
      database: database
    )
    if let namedInstalledPackage, !options.force {
      throw WidgetPackageError.packageAlreadyInstalled(namedInstalledPackage.name)
    }

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
    var replacementTransaction: WidgetPackageReplacementTransaction?
    if namedInstalledPackage != nil {
      replacementTransaction = try WidgetPackageReplacementTransaction.begin(
        packagesDirectory: packagesDirectory,
        fileManager: fileManager
      )
    }
    let installed: [InstalledWidgetPackage]
    do {
      let packages = try await resolver.resolve(source: options.source, sha256: options.sha256)
      guard let rootPackage = packages.last else {
        throw WidgetPackageError.invalidSource("package resolution returned no packages")
      }
      let existingRoot = database.packages.first { $0.name == rootPackage.manifest.name }
      if let existingRoot, !options.force {
        throw WidgetPackageError.packageAlreadyInstalled(existingRoot.name)
      }
      if existingRoot != nil, replacementTransaction == nil {
        replacementTransaction = try WidgetPackageReplacementTransaction.begin(
          packagesDirectory: packagesDirectory,
          fileManager: fileManager
        )
      }

      let replacingExistingPackages: Set<String> =
        existingRoot == nil ? [] : [rootPackage.manifest.name]
      let materializer = WidgetPackageMaterializer(fileManager: fileManager)
      installed = try materializer.install(
        packages,
        into: packagesDirectory,
        database: database,
        stagingDirectory: temporaryDirectory.appending(
          path: "install",
          directoryHint: .isDirectory
        ),
        replacingExistingPackages: replacingExistingPackages
      )
    } catch {
      if let replacementTransaction {
        do {
          try replacementTransaction.rollback()
        } catch let rollbackError {
          throw WidgetPackageError.installConflict(
            "forced install failed (\(error.localizedDescription)); recovery also failed: "
              + rollbackError.localizedDescription
          )
        }
      }
      throw error
    }

    try replacementTransaction?.commit()
    return installed
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

  private func installedPackageNamedBySource(
    _ source: String,
    database: InstalledWidgetPackages
  ) -> InstalledWidgetPackage? {
    let expanded = NSString(string: source).expandingTildeInPath
    guard !fileManager.fileExists(atPath: expanded),
      WidgetPackageManifestParser.isPackageName(source)
    else { return nil }
    return database.packages.first { $0.name == source }
  }

}

func installWidgetPackage(
  options: WidgetPackageInstallOptions,
  context: AppContext
) async throws {
  let spinner = CLIActivitySpinner(message: "Installing \(options.source)…")
  await spinner.start()
  do {
    let installed = try await WidgetPackageInstaller(logger: context.logger).install(options: options)
    await spinner.stop()
    for package in installed {
      fputs("Installed \(package.name) \(package.version) (\(package.kind.rawValue))\n", stdout)
    }
    fputs("Reload EasyBar with: easybar config reload\n", stdout)
  } catch {
    await spinner.stop()
    throw AppError.commandFailed(error.localizedDescription)
  }
}
