import EasyBarShared
import Foundation

/// Stages and atomically activates resolved widget packages with rollback on failure.
struct WidgetPackageMaterializer {
  /// Holds a verified package and its staging and final store locations.
  private struct PreparedPackage {
    /// Package resolved from a registry, directory, or archive.
    let package: ResolvedWidgetPackage
    /// Metadata persisted in the installed-package database.
    let record: InstalledWidgetPackage
    /// Temporary directory containing the uncommitted package contents.
    let stagingURL: URL
    /// Versioned destination under the managed package store.
    let storedURL: URL
  }

  /// Number of package versions retained, including the active version.
  private static let retainedVersionCount = 3

  /// The file manager used for filesystem operations.
  private let fileManager: FileManager

  /// Creates a package materializer using the supplied filesystem implementation.
  init(fileManager: FileManager) {
    self.fileManager = fileManager
  }

  /// Activates a resolved package set and records it only after all replacements succeed.
  func install(
    _ packages: [ResolvedWidgetPackage],
    into packagesDirectory: URL,
    database: InstalledWidgetPackages
  ) throws -> [InstalledWidgetPackage] {
    try validateConflicts(
      packages,
      packagesDirectory: packagesDirectory,
      database: database
    )

    let storeRoot = WidgetPackageStore.storeDirectory(in: packagesDirectory)
    let activeDirectory = WidgetPackageStore.activeDirectory(in: packagesDirectory)
    try fileManager.createDirectory(at: storeRoot, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: activeDirectory, withIntermediateDirectories: true)

    let prepared = try preparePackages(packages, storeRoot: storeRoot)
    defer {
      for package in prepared {
        if itemExists(package.stagingURL) {
          try? fileManager.removeItem(at: package.stagingURL)
        }
        removeDirectoryIfEmpty(package.storedURL.deletingLastPathComponent())
      }
    }

    var updated = database
    var transactions: [WidgetPackageReplacementTransaction] = []

    do {
      for preparedPackage in prepared {
        let transaction = try commit(
          preparedPackage,
          into: packagesDirectory,
          database: &updated
        )
        transactions.append(transaction)
      }
      try WidgetPackageDatabaseStore(fileManager: fileManager).write(
        updated,
        to: packagesDirectory
      )
    } catch {
      do {
        try rollback(transactions)
      } catch let rollbackError {
        throw WidgetPackageError.installConflict(
          "package install failed (\(error.localizedDescription)); recovery also failed: "
            + rollbackError.localizedDescription
        )
      }
      throw error
    }

    for transaction in transactions {
      transaction.commit()
    }
    for preparedPackage in prepared {
      touch(preparedPackage.storedURL)
      pruneStoredVersions(
        for: preparedPackage.record.name,
        activeVersion: preparedPackage.record.version,
        storeRoot: storeRoot
      )
    }

    return prepared.map(\.record)
  }

  /// Rejects collisions with unmanaged widget paths and exports owned by other packages.
  private func validateConflicts(
    _ packages: [ResolvedWidgetPackage],
    packagesDirectory: URL,
    database: InstalledWidgetPackages
  ) throws {
    let activeDirectory = WidgetPackageStore.activeDirectory(in: packagesDirectory)
    let installed = Dictionary(uniqueKeysWithValues: database.packages.map { ($0.name, $0) })
    let exportOwners = Dictionary(
      uniqueKeysWithValues: database.packages.flatMap { package in
        package.exports.keys.map { ($0, package.name) }
      }
    )
    var stagedExports: [String: String] = [:]

    for package in packages {
      let name = package.manifest.name
      if package.manifest.kind == .widget {
        guard name != "shared" else {
          throw WidgetPackageError.installConflict(
            "widget package name 'shared' is reserved for managed library exports"
          )
        }
        let destination = activeDirectory.appending(path: name, directoryHint: .notDirectory)
        if isUnmanagedWidgetCollision(name: name, destination: destination, installed: installed) {
          throw WidgetPackageError.installConflict(
            "\(destination.path) already exists and is not package-managed"
          )
        }
      }

      for module in package.manifest.exports.keys {
        if let owner = stagedExports[module], owner != name {
          throw WidgetPackageError.installConflict(
            "module '\(module)' is exported by both \(owner) and \(name)"
          )
        }
        stagedExports[module] = name
        let destination = moduleURL(module, in: activeDirectory)
        if isModuleOwnershipConflict(
          module: module,
          packageName: name,
          destination: destination,
          exportOwners: exportOwners
        ) {
          throw WidgetPackageError.installConflict(
            "module '\(module)' already exists and is not owned by \(name)"
          )
        }
      }
    }
  }

  /// Copies resolved packages into versioned staging directories before activation.
  private func preparePackages(
    _ packages: [ResolvedWidgetPackage],
    storeRoot: URL
  ) throws -> [PreparedPackage] {
    var prepared: [PreparedPackage] = []

    do {
      for package in packages {
        let record = InstalledWidgetPackage(
          name: package.manifest.name,
          version: package.manifest.version.description,
          kind: package.manifest.kind,
          entrypoint: package.manifest.entrypoint,
          dependencies: package.manifest.dependencies.mapValues(\.rawValue),
          exports: package.manifest.exports,
          source: package.source
        )
        let packageStore = storeRoot.appending(path: record.name, directoryHint: .isDirectory)
        try fileManager.createDirectory(at: packageStore, withIntermediateDirectories: true)
        let stagingURL = packageStore.appending(
          path: "\(record.version).staging-\(UUID().uuidString)",
          directoryHint: .isDirectory
        )
        let storedURL = packageStore.appending(
          path: record.version,
          directoryHint: .isDirectory
        )
        do {
          try prepare(package, at: stagingURL)
        } catch {
          try? fileManager.removeItem(at: stagingURL)
          removeDirectoryIfEmpty(packageStore)
          throw error
        }
        prepared.append(
          PreparedPackage(
            package: package,
            record: record,
            stagingURL: stagingURL,
            storedURL: storedURL
          )
        )
      }
      return prepared
    } catch {
      for package in prepared where itemExists(package.stagingURL) {
        try? fileManager.removeItem(at: package.stagingURL)
      }
      throw error
    }
  }

  /// Copies one resolved package into its staging directory.
  private func prepare(_ package: ResolvedWidgetPackage, at stage: URL) throws {
    try fileManager.copyItem(at: package.directory, to: stage)
  }

  /// Detects an existing unmanaged widget entrypoint at the activation path.
  private func isUnmanagedWidgetCollision(
    name: String,
    destination: URL,
    installed: [String: InstalledWidgetPackage]
  ) -> Bool {
    itemExists(destination) && installed[name] == nil
  }

  /// Detects a Lua module already occupied by another package or unmanaged file.
  private func isModuleOwnershipConflict(
    module: String,
    packageName: String,
    destination: URL,
    exportOwners: [String: String]
  ) -> Bool {
    itemExists(destination) && exportOwners[module] != packageName
  }

  /// Activates the staged package, updates exports, and records its installed metadata.
  private func commit(
    _ prepared: PreparedPackage,
    into packagesDirectory: URL,
    database: inout InstalledWidgetPackages
  ) throws -> WidgetPackageReplacementTransaction {
    let activeDirectory = WidgetPackageStore.activeDirectory(in: packagesDirectory)
    let transaction = WidgetPackageReplacementTransaction(fileManager: fileManager)
    let previous = database.packages.first { $0.name == prepared.record.name }

    do {
      try transaction.replaceItem(
        at: prepared.storedURL,
        with: prepared.stagingURL
      )

      let activeWidget = activeDirectory.appending(
        path: prepared.record.name,
        directoryHint: .notDirectory
      )
      if prepared.package.manifest.kind == .widget,
        let entrypoint = prepared.package.manifest.entrypoint
      {
        try transaction.replaceWithSymbolicLink(
          at: activeWidget,
          to: prepared.storedURL.appending(path: entrypoint, directoryHint: .notDirectory)
        )
      } else if previous?.kind == .widget {
        try transaction.removeItem(at: activeWidget)
      }

      let previousExports = Set(previous?.exports.keys.map { $0 } ?? [])
      let currentExports = Set(prepared.package.manifest.exports.keys)
      for module in previousExports.subtracting(currentExports) {
        try transaction.removeItem(at: moduleURL(module, in: activeDirectory))
      }
      for (module, relativePath) in prepared.package.manifest.exports {
        try transaction.replaceWithSymbolicLink(
          at: moduleURL(module, in: activeDirectory),
          to: prepared.storedURL.appending(path: relativePath, directoryHint: .notDirectory)
        )
      }
    } catch {
      do {
        try transaction.rollback()
      } catch let rollbackError {
        throw WidgetPackageError.installConflict(
          "could not install \(prepared.record.name) (\(error.localizedDescription)); "
            + "recovery also failed: \(rollbackError.localizedDescription)"
        )
      }
      throw error
    }

    database.packages.removeAll { $0.name == prepared.record.name }
    database.packages.append(prepared.record)
    database.packages.sort { $0.name < $1.name }
    return transaction
  }

  /// Restores earlier activation paths in reverse order after a failed batch.
  private func rollback(_ transactions: [WidgetPackageReplacementTransaction]) throws {
    var firstFailure: Error?
    for transaction in transactions.reversed() {
      do {
        try transaction.rollback()
      } catch {
        if firstFailure == nil {
          firstFailure = error
        }
      }
    }
    if let firstFailure {
      throw firstFailure
    }
  }

  /// Removes old inactive package versions while retaining the active version and recent history.
  private func pruneStoredVersions(
    for packageName: String,
    activeVersion: String,
    storeRoot: URL
  ) {
    let packageStore = storeRoot.appending(path: packageName, directoryHint: .isDirectory)
    guard
      let entries = try? fileManager.contentsOfDirectory(
        at: packageStore,
        includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
        options: [.skipsHiddenFiles]
      )
    else { return }

    let versions = entries.compactMap {
      url -> (url: URL, version: SemanticVersion, modified: Date)? in
      guard let version = SemanticVersion(url.lastPathComponent) else { return nil }
      guard
        let values = try? url.resourceValues(forKeys: [
          .isDirectoryKey, .contentModificationDateKey,
        ]),
        values.isDirectory == true
      else { return nil }
      return (url, version, values.contentModificationDate ?? .distantPast)
    }

    let previous =
      versions
      .filter { $0.url.lastPathComponent != activeVersion }
      .sorted { left, right in
        if left.modified != right.modified {
          return left.modified > right.modified
        }
        return left.version > right.version
      }

    var retained = Set([activeVersion])
    retained.formUnion(
      previous.prefix(max(0, Self.retainedVersionCount - 1)).map { $0.url.lastPathComponent }
    )

    for version in versions where !retained.contains(version.url.lastPathComponent) {
      try? fileManager.removeItem(at: version.url)
    }
  }

  /// Removes a package store directory only when it contains no remaining versions.
  private func removeDirectoryIfEmpty(_ url: URL) {
    guard let contents = try? fileManager.contentsOfDirectory(atPath: url.path), contents.isEmpty
    else { return }
    try? fileManager.removeItem(at: url)
  }

  /// Marks the installed version as recently used for retention ordering.
  private func touch(_ url: URL) {
    try? fileManager.setAttributes(
      [.modificationDate: Date()],
      ofItemAtPath: url.path
    )
  }

  /// Maps a dotted Lua module name to its managed shared-file path.
  private func moduleURL(_ module: String, in root: URL) -> URL {
    let path = module.replacing(".", with: "/") + ".lua"
    return root.appending(path: "shared").appending(path: path)
  }

  /// Returns whether a path contains a file or symbolic link.
  private func itemExists(_ url: URL) -> Bool {
    fileManager.fileExists(atPath: url.path)
      || (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) != nil
  }

}
