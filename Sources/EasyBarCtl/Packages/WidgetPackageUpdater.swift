import EasyBarShared
import Foundation

/// Stores outdated widget package data.
struct OutdatedWidgetPackage: Equatable {
  /// The name for this outdated widget package.
  let name: String
  /// The installed version for this outdated widget package.
  let installedVersion: String
  /// The available version for this outdated widget package.
  let availableVersion: String
  /// The kind for this outdated widget package.
  let kind: WidgetPackageKind
  /// Whether this outdated widget package is pinned.
  let pinned: Bool
}

/// Stores widget package change data.
struct WidgetPackageChange: Equatable {
  /// The package for this widget package change.
  let package: InstalledWidgetPackage
  /// The previous version for this widget package change.
  let previousVersion: String?
}

/// Stores widget package update result data.
struct WidgetPackageUpdateResult: Equatable {
  /// The changes for this widget package update result.
  let changes: [WidgetPackageChange]
  /// The skipped pinned for this widget package update result.
  let skippedPinned: [String]
  /// The reload plan for this widget package update result.
  let reloadPlan: WidgetPackageReloadPlan
}

/// Stores the package names selected for update and pinned names skipped by policy.
private struct ResolvedWidgetPackageUpdateSelection {
  /// Package names that remain eligible for an update.
  let targets: [String]
  /// Pinned package names omitted from an all-packages update.
  let skippedPinned: Set<String>
}

/// Coordinates widget package updater state and behavior.
final class WidgetPackageUpdater {
  private let packagesDirectory: URL
  private let databaseStore: WidgetPackageDatabaseStore
  private let pinStore: WidgetPackagePinStore
  private let registryLoader: WidgetPackageRegistryLoader
  private let installer: WidgetPackageInstaller

  /// Creates a widget package updater.
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

  /// Finds outdated packages.
  func outdated(
    registrySource: String?,
    refreshRegistry: Bool = false
  ) async throws -> [OutdatedWidgetPackage] {
    let database = try databaseStore.load(from: packagesDirectory)
    let pins = try pinStore.load(from: packagesDirectory)
    let registry = try await registryLoader.load(
      source: registrySource,
      refresh: refreshRegistry
    )
    return try outdatedPackages(database: database, registry: registry, pins: pins)
  }

  /// Updates the requested operation.
  func update(options: WidgetPackageUpdateOptions) async throws -> WidgetPackageUpdateResult {
    let initialDatabase = try databaseStore.load(from: packagesDirectory)
    let initialPins = try pinStore.load(from: packagesDirectory)
    let registry = try await registryLoader.load(
      source: options.registry,
      refresh: options.refreshRegistry
    )
    let entries = Dictionary(uniqueKeysWithValues: registry.packages.map { ($0.name, $0) })
    let selection = try updateSelection(
      options.selection,
      database: initialDatabase,
      registry: registry,
      pins: initialPins
    )
    var skippedPinned = selection.skippedPinned

    var touchedNames: Set<String> = []
    for name in selection.targets {
      let currentDatabase = try databaseStore.load(from: packagesDirectory)
      let currentPins = try pinStore.load(from: packagesDirectory)
      if currentPins.contains(name) {
        skippedPinned.insert(name)
        continue
      }
      guard
        try isEligibleUpdateTarget(
          name,
          database: currentDatabase,
          registryEntries: entries
        )
      else {
        continue
      }

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
    let reloadPlan = try WidgetPackageReloadPlanner.make(
      changedNames: Set(changes.map(\.package.name)),
      packages: finalDatabase.packages
    )

    return WidgetPackageUpdateResult(
      changes: changes,
      skippedPinned: skippedPinned.sorted(),
      reloadPlan: reloadPlan
    )
  }

  /// Applies explicit-versus-all update policy and returns the resulting package selection.
  private func updateSelection(
    _ requestedSelection: WidgetPackageUpdateSelection,
    database: InstalledWidgetPackages,
    registry: PackageRegistryIndex,
    pins: Set<String>
  ) throws -> ResolvedWidgetPackageUpdateSelection {
    let entries = Dictionary(uniqueKeysWithValues: registry.packages.map { ($0.name, $0) })

    switch requestedSelection {
    case .package(let name):
      guard let installed = database.packages.first(where: { $0.name == name }) else {
        throw WidgetPackageError.packageNotInstalled(name)
      }
      if pins.contains(name) {
        throw WidgetPackageError.packagePinned(name)
      }
      guard let entry = entries[name] else {
        throw WidgetPackageError.unavailablePackage(name)
      }
      guard releaseSources(entry).contains(installed.source) else {
        throw WidgetPackageError.packageNotManagedByRegistry(name)
      }
      let targets = try isOutdated(installed, comparedWith: entry) ? [name] : []
      return ResolvedWidgetPackageUpdateSelection(targets: targets, skippedPinned: [])

    case .all:
      let outdated = try outdatedPackages(database: database, registry: registry, pins: pins)
      let targets = outdated.filter { !$0.pinned }
        .sorted(by: updatePriority)
        .map(\.name)
      return ResolvedWidgetPackageUpdateSelection(
        targets: targets,
        skippedPinned: Set(outdated.filter(\.pinned).map(\.name))
      )
    }
  }

  /// Returns whether one selected package still needs an update from its owning registry.
  private func isEligibleUpdateTarget(
    _ name: String,
    database: InstalledWidgetPackages,
    registryEntries: [String: PackageRegistryEntry]
  ) throws -> Bool {
    guard let installed = database.packages.first(where: { $0.name == name }) else {
      return false
    }
    guard let entry = registryEntries[name] else {
      return false
    }
    guard releaseSources(entry).contains(installed.source) else {
      return false
    }
    return try isOutdated(installed, comparedWith: entry)
  }

  /// Orders widgets before libraries, then orders packages by name.
  private func updatePriority(_ left: OutdatedWidgetPackage, _ right: OutdatedWidgetPackage) -> Bool {
    if left.kind != right.kind {
      return left.kind == .widget
    }
    return left.name < right.name
  }

  /// Returns the outdated packages.
  private func outdatedPackages(
    database: InstalledWidgetPackages,
    registry: PackageRegistryIndex,
    pins: Set<String>
  ) throws -> [OutdatedWidgetPackage] {
    let entries = Dictionary(uniqueKeysWithValues: registry.packages.map { ($0.name, $0) })
    return try database.packages.compactMap {
      try outdatedPackage($0, registryEntries: entries, pins: pins)
    }.sorted { $0.name < $1.name }
  }

  /// Builds update status for one registry-managed outdated package.
  private func outdatedPackage(
    _ installed: InstalledWidgetPackage,
    registryEntries: [String: PackageRegistryEntry],
    pins: Set<String>
  ) throws -> OutdatedWidgetPackage? {
    guard let entry = registryEntries[installed.name] else {
      return nil
    }
    guard releaseSources(entry).contains(installed.source) else {
      return nil
    }
    guard try isOutdated(installed, comparedWith: entry) else {
      return nil
    }
    return OutdatedWidgetPackage(
      name: installed.name,
      installedVersion: installed.version,
      availableVersion: entry.latest,
      kind: installed.kind,
      pinned: pins.contains(installed.name)
    )
  }

  /// Evaluates the outdated condition.
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

  /// Returns the release sources.
  private func releaseSources(_ entry: PackageRegistryEntry) -> Set<String> {
    Set(entry.versions.map(\.archive))
  }
}

/// Lists outdated widget packages.
func listOutdatedWidgetPackages(
  options: WidgetPackageRegistryOptions,
  context: AppContext
) async throws {
  do {
    context.debug("checking for outdated widget packages")
    let packages = try await WidgetPackageUpdater(logger: context.logger).outdated(
      registrySource: options.registry,
      refreshRegistry: options.refreshRegistry
    )
    CLIOutput.printOutdatedWidgetPackages(packages)
  } catch {
    throw AppError.commandFailed(error.localizedDescription)
  }
}

/// Updates widget packages.
func updateWidgetPackages(options: WidgetPackageUpdateOptions, context: AppContext) async throws {
  let label: String
  switch options.selection {
  case .package(let name): label = "Updating \(name)…"
  case .all: label = "Updating widget packages…"
  }
  let spinner = CLIActivitySpinner(message: label)
  await spinner.start()
  do {
    let packagesDirectory = SharedPathDefaults.defaultWidgetPackagesPath()
    let updater = WidgetPackageUpdater(
      logger: context.logger,
      packagesDirectory: packagesDirectory
    )
    let result = try await updater.update(options: options)
    await spinner.stop()
    CLIOutput.printWidgetPackageUpdateResult(result)
    requestRuntimeReload(
      result.reloadPlan,
      packagesDirectory: packagesDirectory,
      context: context
    )
  } catch {
    await spinner.stop()
    throw AppError.commandFailed(error.localizedDescription)
  }
}

/// Requests runtime reload.
private func requestRuntimeReload(
  _ plan: WidgetPackageReloadPlan,
  packagesDirectory: URL,
  context: AppContext
) {
  guard !plan.isEmpty else { return }

  let store = WidgetPackageReloadPlanStore()
  do {
    try store.write(plan, to: packagesDirectory)
    let resolution = try SharedRuntimeSocketResolver.controlSocket(explicitPath: nil)
    logSocketResolution(resolution, kind: "control", context: context)
    try sendCommand(.manualRefresh, to: resolution.path, context: context)
  } catch {
    store.remove(from: packagesDirectory)
    fputs(
      "warning: widget packages were updated but the running Lua runtime could not be reloaded: "
        + error.localizedDescription + "\n",
      stderr
    )
  }
}
