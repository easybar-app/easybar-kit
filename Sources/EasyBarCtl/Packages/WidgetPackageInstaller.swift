import EasyBarShared
import Foundation

final class WidgetPackageInstaller {
  private let logger: ProcessLogger
  private let fileManager: FileManager
  private let packagesDirectory: URL

  init(
    logger: ProcessLogger,
    fileManager: FileManager = .default,
    packagesDirectory: URL = SharedPathDefaults.defaultWidgetPackagesPath()
  ) {
    self.logger = logger
    self.fileManager = fileManager
    self.packagesDirectory = packagesDirectory
  }

  func install(options: WidgetPackageInstallOptions) async throws -> [InstalledWidgetPackage] {
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
      temporaryDirectory: temporaryDirectory.appending(
        path: "downloads", directoryHint: .isDirectory),
      installed: database.packages,
      logger: logger
    )
    try fileManager.createDirectory(
      at: temporaryDirectory.appending(path: "downloads", directoryHint: .isDirectory),
      withIntermediateDirectories: true
    )
    let packages = try await resolver.resolve(source: options.source, sha256: options.sha256)
    guard let rootPackage = packages.last else {
      throw WidgetPackageError.invalidSource("package resolution returned no packages")
    }
    if let existingRoot = database.packages.first(where: { $0.name == rootPackage.manifest.name }),
      !options.force
    {
      throw WidgetPackageError.packageAlreadyInstalled(existingRoot.name)
    }

    return try WidgetPackageMaterializer(fileManager: fileManager).install(
      packages,
      into: packagesDirectory,
      database: database
    )
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
    let installed = try await WidgetPackageInstaller(logger: context.logger).install(
      options: options)
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
