import EasyBarShared
import Foundation

struct WidgetPackageMaterializer {
  private let fileManager: FileManager

  init(fileManager: FileManager) {
    self.fileManager = fileManager
  }

  func install(
    _ packages: [ResolvedWidgetPackage],
    into packagesDirectory: URL,
    database: InstalledWidgetPackages,
    stagingDirectory: URL
  ) throws -> [InstalledWidgetPackage] {
    try validateConflicts(
      packages,
      packagesDirectory: packagesDirectory,
      database: database
    )
    try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)

    var records: [InstalledWidgetPackage] = []
    for package in packages {
      let packageStage = stagingDirectory.appending(
        path: package.manifest.name,
        directoryHint: .isDirectory
      )
      try prepare(package, at: packageStage)
      records.append(
        InstalledWidgetPackage(
          name: package.manifest.name,
          version: package.manifest.version.description,
          kind: package.manifest.kind,
          entrypoint: package.manifest.entrypoint,
          dependencies: package.manifest.dependencies.mapValues(\.rawValue),
          exports: package.manifest.exports,
          source: package.source
        )
      )
    }

    var updated = database
    for (package, record) in zip(packages, records) {
      try commit(
        package,
        record: record,
        from: stagingDirectory.appending(path: package.manifest.name),
        into: packagesDirectory,
        database: &updated
      )
    }
    try write(updated, to: packagesDirectory.appending(path: "installed.json"))
    return records
  }

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
        let destination = activeDirectory.appending(path: name, directoryHint: .isDirectory)
        if fileManager.fileExists(atPath: destination.path), installed[name] == nil {
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
        if fileManager.fileExists(atPath: destination.path),
          exportOwners[module] != name
        {
          throw WidgetPackageError.installConflict(
            "module '\(module)' already exists and is not owned by \(name)"
          )
        }
      }
    }
  }

  private func prepare(_ package: ResolvedWidgetPackage, at stage: URL) throws {
    let store = stage.appending(path: "store", directoryHint: .isDirectory)
    try fileManager.createDirectory(at: stage, withIntermediateDirectories: true)
    try fileManager.copyItem(at: package.directory, to: store)

    if package.manifest.kind == .widget, let entrypoint = package.manifest.entrypoint {
      let projection = stage.appending(path: "widget", directoryHint: .isDirectory)
      try copyWidgetProjection(
        from: store,
        to: projection,
        entrypoint: entrypoint,
        exports: Set(package.manifest.exports.values)
      )
    }

    let modules = stage.appending(path: "modules", directoryHint: .isDirectory)
    for (module, relativePath) in package.manifest.exports {
      let destination = moduleURL(module, in: modules)
      try fileManager.createDirectory(
        at: destination.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try fileManager.copyItem(at: store.appending(path: relativePath), to: destination)
    }
  }

  private func copyWidgetProjection(
    from source: URL,
    to destination: URL,
    entrypoint: String,
    exports: Set<String>
  ) throws {
    try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
    guard let enumerator = fileManager.enumerator(atPath: source.path) else {
      throw WidgetPackageError.invalidSource("could not enumerate \(source.path)")
    }

    for case let relative as String in enumerator {
      let file = source.appending(path: relative)
      let values = try file.resourceValues(forKeys: [.isRegularFileKey])
      guard values.isRegularFile == true else { continue }
      if file.pathExtension.lowercased() == "lua",
        relative != entrypoint,
        !exports.contains(relative)
      {
        continue
      }
      if exports.contains(relative), relative != entrypoint { continue }

      let output = destination.appending(path: relative)
      try fileManager.createDirectory(
        at: output.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try fileManager.copyItem(at: file, to: output)
    }
  }

  private func commit(
    _ package: ResolvedWidgetPackage,
    record: InstalledWidgetPackage,
    from stage: URL,
    into packagesDirectory: URL,
    database: inout InstalledWidgetPackages
  ) throws {
    let storeRoot = WidgetPackageStore.storeDirectory(in: packagesDirectory)
    let activeDirectory = WidgetPackageStore.activeDirectory(in: packagesDirectory)
    try fileManager.createDirectory(at: storeRoot, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: activeDirectory, withIntermediateDirectories: true)

    if let previous = database.packages.first(where: { $0.name == record.name }) {
      if previous.kind == .widget {
        try removeIfPresent(activeDirectory.appending(path: previous.name))
      }
      for module in previous.exports.keys {
        try removeIfPresent(moduleURL(module, in: activeDirectory))
      }
    }
    let storedPackage =
      storeRoot
      .appending(path: record.name, directoryHint: .isDirectory)
      .appending(path: record.version, directoryHint: .isDirectory)
    try removeIfPresent(storedPackage)
    try fileManager.createDirectory(
      at: storedPackage.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try fileManager.moveItem(
      at: stage.appending(path: "store"),
      to: storedPackage
    )

    if package.manifest.kind == .widget {
      try fileManager.moveItem(
        at: stage.appending(path: "widget"),
        to: activeDirectory.appending(path: record.name)
      )
    }
    let modules = stage.appending(path: "modules", directoryHint: .isDirectory)
    for module in package.manifest.exports.keys {
      let source = moduleURL(module, in: modules)
      let destination = moduleURL(module, in: activeDirectory)
      try fileManager.createDirectory(
        at: destination.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try fileManager.moveItem(at: source, to: destination)
    }

    database.packages.removeAll { $0.name == record.name }
    database.packages.append(record)
    database.packages.sort { $0.name < $1.name }
  }

  private func moduleURL(_ module: String, in root: URL) -> URL {
    let path = module.replacing(".", with: "/") + ".lua"
    return root.appending(path: "shared").appending(path: path)
  }

  private func removeIfPresent(_ url: URL) throws {
    if fileManager.fileExists(atPath: url.path) {
      try fileManager.removeItem(at: url)
    }
  }

  private func write(_ database: InstalledWidgetPackages, to url: URL) throws {
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
