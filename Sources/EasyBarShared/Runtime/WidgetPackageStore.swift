import Foundation

/// Filesystem layout and migration support for managed Lua widget packages.
public enum WidgetPackageStore {
  public static let layoutVersion = 2

  /// Returns the directory containing activated widget projections and exported modules.
  public static func activeDirectory(in packagesDirectory: URL) -> URL {
    packagesDirectory.appending(path: "active", directoryHint: .isDirectory)
  }

  /// Returns the directory containing immutable package source snapshots.
  public static func storeDirectory(in packagesDirectory: URL) -> URL {
    packagesDirectory.appending(path: "store", directoryHint: .isDirectory)
  }

  /// Migrates the legacy package-managed files out of a manual widgets directory.
  @discardableResult
  public static func migrateLegacyInstallation(
    from widgetsDirectory: URL,
    to packagesDirectory: URL,
    fileManager: FileManager = .default
  ) throws -> Bool {
    let legacyMetadata = widgetsDirectory.appending(path: ".easybar", directoryHint: .isDirectory)
    let legacyDatabaseURL = legacyMetadata.appending(path: "installed.json")
    guard fileManager.fileExists(atPath: legacyDatabaseURL.path) else { return false }

    let legacy = try decodeDatabase(at: legacyDatabaseURL)
    guard legacy.layoutVersion == 1 else {
      throw WidgetPackageStoreError.unsupportedLegacyLayout(legacy.layoutVersion)
    }

    let databaseURL = packagesDirectory.appending(path: "installed.json")
    if fileManager.fileExists(atPath: databaseURL.path) {
      try validateCompletedMigration(
        legacy,
        databaseURL: databaseURL,
        packagesDirectory: packagesDirectory,
        fileManager: fileManager
      )
    } else {
      try createMigratedStore(
        legacy,
        legacyMetadata: legacyMetadata,
        widgetsDirectory: widgetsDirectory,
        packagesDirectory: packagesDirectory,
        fileManager: fileManager
      )
    }

    try removeLegacyActivation(
      legacy,
      legacyMetadata: legacyMetadata,
      widgetsDirectory: widgetsDirectory,
      fileManager: fileManager
    )
    return true
  }

  private static func validateCompletedMigration(
    _ legacy: PackageDatabase,
    databaseURL: URL,
    packagesDirectory: URL,
    fileManager: FileManager
  ) throws {
    let current = try decodeDatabase(at: databaseURL)
    guard current.layoutVersion == layoutVersion else {
      throw WidgetPackageStoreError.unsupportedDestinationLayout(current.layoutVersion)
    }

    let currentNames = Set(current.packages.map(\.name))
    let legacyNames = Set(legacy.packages.map(\.name))
    let missingNames = legacyNames.filter { !currentNames.contains($0) }.sorted()
    guard missingNames.isEmpty else {
      throw WidgetPackageStoreError.incompleteMigrationDestination(
        packagesDirectory.path,
        missingNames
      )
    }

    for package in current.packages where legacyNames.contains(package.name) {
      try validate(package)
      let storedSource = storeDirectory(in: packagesDirectory)
        .appending(path: package.name, directoryHint: .isDirectory)
        .appending(path: package.version, directoryHint: .isDirectory)
      guard fileManager.fileExists(atPath: storedSource.path) else {
        throw WidgetPackageStoreError.missingManagedPath(storedSource.path)
      }

      let active = activeDirectory(in: packagesDirectory)
      if package.kind == "widget" {
        let activeWidget = active.appending(path: package.name, directoryHint: .isDirectory)
        guard fileManager.fileExists(atPath: activeWidget.path) else {
          throw WidgetPackageStoreError.missingManagedPath(activeWidget.path)
        }
      }
      for module in package.exports.keys {
        let activeModule = active.appending(path: "shared/\(try moduleRelativePath(module))")
        guard fileManager.fileExists(atPath: activeModule.path) else {
          throw WidgetPackageStoreError.missingManagedPath(activeModule.path)
        }
      }
    }
  }

  private static func createMigratedStore(
    _ legacy: PackageDatabase,
    legacyMetadata: URL,
    widgetsDirectory: URL,
    packagesDirectory: URL,
    fileManager: FileManager
  ) throws {
    let parent = packagesDirectory.deletingLastPathComponent()
    try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
    guard !fileManager.fileExists(atPath: packagesDirectory.path) else {
      throw WidgetPackageStoreError.destinationAlreadyExists(packagesDirectory.path)
    }

    let stage = parent.appending(
      path: ".easybar-packages-migration-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    defer { try? fileManager.removeItem(at: stage) }
    try fileManager.createDirectory(at: stage, withIntermediateDirectories: true)

    for package in legacy.packages {
      try validate(package)
      let legacySource = legacyMetadata.appending(path: "packages/\(package.name)")
      let storedSource = storeDirectory(in: stage)
        .appending(path: package.name, directoryHint: .isDirectory)
        .appending(path: package.version, directoryHint: .isDirectory)
      try copyRequired(
        from: legacySource,
        to: storedSource,
        label: "stored package \(package.name)",
        fileManager: fileManager
      )

      if package.kind == "widget" {
        try copyRequired(
          from: widgetsDirectory.appending(path: package.name, directoryHint: .isDirectory),
          to: activeDirectory(in: stage).appending(
            path: package.name,
            directoryHint: .isDirectory
          ),
          label: "active widget \(package.name)",
          fileManager: fileManager
        )
      }

      for module in package.exports.keys {
        let relativePath = try moduleRelativePath(module)
        try copyRequired(
          from: widgetsDirectory.appending(path: "shared/\(relativePath)"),
          to: activeDirectory(in: stage).appending(path: "shared/\(relativePath)"),
          label: "exported module \(module)",
          fileManager: fileManager
        )
      }
    }

    var migrated = legacy
    migrated.layoutVersion = layoutVersion
    try writeDatabase(migrated, to: stage.appending(path: "installed.json"))
    try fileManager.moveItem(at: stage, to: packagesDirectory)
  }

  private static func removeLegacyActivation(
    _ legacy: PackageDatabase,
    legacyMetadata: URL,
    widgetsDirectory: URL,
    fileManager: FileManager
  ) throws {
    for package in legacy.packages {
      try validate(package)
      if package.kind == "widget" {
        try removeIfPresent(
          widgetsDirectory.appending(path: package.name, directoryHint: .isDirectory),
          fileManager: fileManager
        )
      }
      for module in package.exports.keys {
        let relativePath = try moduleRelativePath(module)
        let moduleURL = widgetsDirectory.appending(path: "shared/\(relativePath)")
        try removeIfPresent(moduleURL, fileManager: fileManager)
        try removeEmptyParents(
          from: moduleURL.deletingLastPathComponent(),
          through: widgetsDirectory.appending(path: "shared", directoryHint: .isDirectory),
          fileManager: fileManager
        )
      }
    }
    try removeIfPresent(legacyMetadata, fileManager: fileManager)
  }

  private static func validate(_ package: PackageRecord) throws {
    guard package.name.range(of: #"^[a-z0-9]+(?:-[a-z0-9]+)*$"#, options: .regularExpression) != nil else {
      throw WidgetPackageStoreError.invalidLegacyRecord(package.name)
    }
    guard
      package.version.range(of: #"^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?$"#, options: .regularExpression) != nil
    else {
      throw WidgetPackageStoreError.invalidLegacyRecord(package.name)
    }
    guard package.kind == "widget" || package.kind == "library" else {
      throw WidgetPackageStoreError.invalidLegacyRecord(package.name)
    }
    for module in package.exports.keys {
      _ = try moduleRelativePath(module)
    }
  }

  private static func moduleRelativePath(_ module: String) throws -> String {
    guard module.range(of: #"^[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)*$"#, options: .regularExpression) != nil else {
      throw WidgetPackageStoreError.invalidExport(module)
    }
    return module.replacing(".", with: "/") + ".lua"
  }

  private static func copyRequired(
    from source: URL,
    to destination: URL,
    label: String,
    fileManager: FileManager
  ) throws {
    guard fileManager.fileExists(atPath: source.path) else {
      throw WidgetPackageStoreError.missingLegacyPath(label, source.path)
    }
    try fileManager.createDirectory(
      at: destination.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try fileManager.copyItem(at: source, to: destination)
  }

  private static func removeIfPresent(_ url: URL, fileManager: FileManager) throws {
    if fileManager.fileExists(atPath: url.path) {
      try fileManager.removeItem(at: url)
    }
  }

  private static func removeEmptyParents(
    from start: URL,
    through boundary: URL,
    fileManager: FileManager
  ) throws {
    var directory = start
    while directory.path.hasPrefix(boundary.path) {
      let contents = try fileManager.contentsOfDirectory(atPath: directory.path)
      guard contents.isEmpty else { return }
      try fileManager.removeItem(at: directory)
      if directory.standardizedFileURL == boundary.standardizedFileURL { return }
      directory.deleteLastPathComponent()
    }
  }

  private static func decodeDatabase(at url: URL) throws -> PackageDatabase {
    do {
      return try JSONDecoder().decode(PackageDatabase.self, from: Data(contentsOf: url))
    } catch {
      throw WidgetPackageStoreError.invalidDatabase(url.path, error.localizedDescription)
    }
  }

  private static func writeDatabase(_ database: PackageDatabase, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    var data = try encoder.encode(database)
    data.append(0x0A)
    try data.write(to: url, options: .atomic)
  }

  private struct PackageDatabase: Codable {
    var layoutVersion: Int
    let packages: [PackageRecord]

    private enum CodingKeys: String, CodingKey {
      case layoutVersion = "layout_version"
      case packages
    }
  }

  private struct PackageRecord: Codable {
    let name: String
    let version: String
    let kind: String
    let entrypoint: String?
    let dependencies: [String: String]
    let exports: [String: String]
    let source: String
  }
}

/// Failures produced while migrating the legacy package layout.
public enum WidgetPackageStoreError: LocalizedError {
  case unsupportedLegacyLayout(Int)
  case unsupportedDestinationLayout(Int)
  case destinationAlreadyExists(String)
  case incompleteMigrationDestination(String, [String])
  case missingManagedPath(String)
  case invalidLegacyRecord(String)
  case invalidExport(String)
  case missingLegacyPath(String, String)
  case invalidDatabase(String, String)

  public var errorDescription: String? {
    switch self {
    case .unsupportedLegacyLayout(let version):
      return "unsupported legacy widget package layout \(version)"
    case .unsupportedDestinationLayout(let version):
      return "unsupported managed widget package layout \(version)"
    case .destinationAlreadyExists(let path):
      return "widget package destination already exists without metadata: \(path)"
    case .incompleteMigrationDestination(let path, let names):
      return "managed widget package store at \(path) is missing legacy packages: \(names.joined(separator: ", "))"
    case .missingManagedPath(let path):
      return "managed widget package store is missing expected path: \(path)"
    case .invalidLegacyRecord(let name):
      return "invalid legacy widget package record: \(name)"
    case .invalidExport(let module):
      return "invalid legacy widget package export: \(module)"
    case .missingLegacyPath(let label, let path):
      return "missing \(label) at \(path)"
    case .invalidDatabase(let path, let message):
      return "could not read widget package database at \(path): \(message)"
    }
  }
}
