import EasyBarShared
import Foundation

struct OutdatedWidgetPackage: Equatable {
  let name: String
  let installedVersion: String
  let availableVersion: String
  let kind: WidgetPackageKind
  let pinned: Bool
}

struct WidgetPackageChange: Equatable {
  let package: InstalledWidgetPackage
  let previousVersion: String?
}

struct WidgetPackageUpdateResult: Equatable {
  let changes: [WidgetPackageChange]
  let skippedPinned: [String]
}

final class WidgetPackageUpdater {
  private let packagesDirectory: URL
  private let databaseStore: WidgetPackageDatabaseStore
  private let pinStore: WidgetPackagePinStore
  private let registryLoader: WidgetPackageRegistryLoader
  private let installer: WidgetPackageInstaller

  init(
    logger: ProcessLogger,
    fileManager: FileManager = .default,
    packagesDirectory: URL = SharedPathDefaults.defaultWidgetPackagesPath(),
    registryLoader: WidgetPackageRegistryLoader = WidgetPackageRegistryLoader()
  ) {
    self.packagesDirectory = packagesDirectory
    self.registryLoader = registryLoader
    databaseStore = WidgetPackageDatabaseStore(fileManager: fileManager)
    pinStore = WidgetPackagePinStore(fileManager: fileManager)
    installer = WidgetPackageInstaller(
      logger: logger,
      fileManager: fileManager,
      packagesDirectory: packagesDirectory
    )
  }

  func outdated(registrySource: String?) async throws -> [OutdatedWidgetPackage] {
    let database = try databaseStore.load(from: packagesDirectory)
    let pins = try pinStore.load(from: packagesDirectory)
    let registry = try await registryLoader.load(source: registrySource)
    return try outdatedPackages(database: database, registry: registry, pins: pins)
  }

  func update(options: WidgetPackageUpdateOptions) async throws -> WidgetPackageUpdateResult {
    let initialDatabase = try databaseStore.load(from: packagesDirectory)
    let initialPins = try pinStore.load(from: packagesDirectory)
    let registry = try await registryLoader.load(source: options.registry)
    let entries = Dictionary(uniqueKeysWithValues: registry.packages.map { ($0.name, $0) })
    let targets: [String]
    var skippedPinned: Set<String> = []

    switch options.selection {
    case .package(let name):
      guard let installed = initialDatabase.packages.first(where: { $0.name == name }) else {
        throw WidgetPackageError.packageNotInstalled(name)
      }
      if initialPins.contains(name) {
        throw WidgetPackageError.packagePinned(name)
      }
      guard let entry = entries[name] else {
        throw WidgetPackageError.unavailablePackage(name)
      }
      guard releaseSources(entry).contains(installed.source) else {
        throw WidgetPackageError.packageNotManagedByRegistry(name)
      }
      targets = try isOutdated(installed, comparedWith: entry) ? [name] : []

    case .all:
      let outdated = try outdatedPackages(
        database: initialDatabase,
        registry: registry,
        pins: initialPins
      )
      skippedPinned.formUnion(outdated.filter(\.pinned).map(\.name))
      targets = outdated.filter { !$0.pinned }
        .sorted { left, right in
          if left.kind != right.kind { return left.kind == .widget }
          return left.name < right.name
        }
        .map(\.name)
    }

    var touchedNames: Set<String> = []
    for name in targets {
      let currentDatabase = try databaseStore.load(from: packagesDirectory)
      let currentPins = try pinStore.load(from: packagesDirectory)
      if currentPins.contains(name) {
        skippedPinned.insert(name)
        continue
      }
      guard let current = currentDatabase.packages.first(where: { $0.name == name }),
        let entry = entries[name],
        releaseSources(entry).contains(current.source),
        try isOutdated(current, comparedWith: entry)
      else { continue }

      let installed = try await installer.install(
        options: WidgetPackageInstallOptions(
          source: name,
          sha256: nil,
          registry: options.registry,
          useRegistry: true,
          force: true
        ),
        protectedPackages: currentPins
      )
      touchedNames.formUnion(installed.map(\.name))
    }

    let previous = Dictionary(uniqueKeysWithValues: initialDatabase.packages.map { ($0.name, $0) })
    let finalDatabase = try databaseStore.load(from: packagesDirectory)
    let changes = finalDatabase.packages
      .filter { touchedNames.contains($0.name) && previous[$0.name]?.version != $0.version }
      .map { WidgetPackageChange(package: $0, previousVersion: previous[$0.name]?.version) }
      .sorted { $0.package.name < $1.package.name }

    return WidgetPackageUpdateResult(
      changes: changes,
      skippedPinned: skippedPinned.sorted()
    )
  }

  private func outdatedPackages(
    database: InstalledWidgetPackages,
    registry: PackageRegistryIndex,
    pins: Set<String>
  ) throws -> [OutdatedWidgetPackage] {
    let entries = Dictionary(uniqueKeysWithValues: registry.packages.map { ($0.name, $0) })
    return try database.packages.compactMap { installed in
      guard let entry = entries[installed.name], releaseSources(entry).contains(installed.source),
        try isOutdated(installed, comparedWith: entry)
      else { return nil }
      return OutdatedWidgetPackage(
        name: installed.name,
        installedVersion: installed.version,
        availableVersion: entry.latest,
        kind: installed.kind,
        pinned: pins.contains(installed.name)
      )
    }.sorted { $0.name < $1.name }
  }

  private func isOutdated(
    _ installed: InstalledWidgetPackage,
    comparedWith entry: PackageRegistryEntry
  ) throws -> Bool {
    guard entry.versions.contains(where: { $0.version == entry.latest }),
      let availableVersion = SemanticVersion(entry.latest)
    else {
      throw WidgetPackageError.invalidRegistry(
        "package '\(entry.name)' has an invalid latest version"
      )
    }
    guard let installedVersion = SemanticVersion(installed.version) else {
      throw WidgetPackageError.installConflict(
        "package '\(installed.name)' has invalid installed version '\(installed.version)'"
      )
    }
    return installedVersion < availableVersion
  }

  private func releaseSources(_ entry: PackageRegistryEntry) -> Set<String> {
    Set(entry.versions.map(\.archive))
  }
}

func listOutdatedWidgetPackages(registrySource: String?, context: AppContext) async throws {
  do {
    context.debug("checking for outdated widget packages")
    let packages = try await WidgetPackageUpdater(logger: context.logger).outdated(
      registrySource: registrySource
    )
    CLIOutput.printOutdatedWidgetPackages(packages)
  } catch {
    throw AppError.commandFailed(error.localizedDescription)
  }
}

func updateWidgetPackages(options: WidgetPackageUpdateOptions, context: AppContext) async throws {
  let label: String
  switch options.selection {
  case .package(let name): label = "Updating \(name)…"
  case .all: label = "Updating widget packages…"
  }
  let spinner = CLIActivitySpinner(message: label)
  await spinner.start()
  do {
    let result = try await WidgetPackageUpdater(logger: context.logger).update(options: options)
    await spinner.stop()
    CLIOutput.printWidgetPackageUpdateResult(result)
  } catch {
    await spinner.stop()
    throw AppError.commandFailed(error.localizedDescription)
  }
}
