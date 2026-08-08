import EasyBarShared
import Foundation

final class WidgetPackageInstaller {
  private let logger: ProcessLogger
  private let fileManager: FileManager

  init(logger: ProcessLogger, fileManager: FileManager = .default) {
    self.logger = logger
    self.fileManager = fileManager
  }

  func install(options: WidgetPackageInstallOptions) async throws -> [InstalledWidgetPackage] {
    let widgetsDirectory = try resolvedWidgetsDirectory(options.widgetsDirectory)
    try fileManager.createDirectory(at: widgetsDirectory, withIntermediateDirectories: true)
    let metadataDirectory = widgetsDirectory.appending(path: ".easybar", directoryHint: .isDirectory)
    let databaseURL = metadataDirectory.appending(path: "installed.json")
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
      into: widgetsDirectory,
      database: database,
      stagingDirectory: temporaryDirectory.appending(path: "install", directoryHint: .isDirectory)
    )
  }

  private func resolvedWidgetsDirectory(_ configured: String?) throws -> URL {
    guard let configured else {
      do {
        return URL(fileURLWithPath: try SharedRuntimeConfig.load().app.widgetsPath, isDirectory: true)
      } catch {
        throw WidgetPackageError.invalidSource(
          "could not resolve widgets_dir from config: \(error.localizedDescription)"
        )
      }
    }
    let path = NSString(string: configured).expandingTildeInPath
    guard !path.isEmpty else {
      throw WidgetPackageError.invalidSource("--widgets-dir cannot be empty")
    }
    return URL(fileURLWithPath: path, isDirectory: true)
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
    guard decoded.layoutVersion == 1 else {
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
