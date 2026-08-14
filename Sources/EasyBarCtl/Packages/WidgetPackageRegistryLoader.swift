import Foundation

struct WidgetPackageRegistryLoader {
  static let defaultSource =
    "https://raw.githubusercontent.com/easybar-app/registry/main/index.json"
  private static let maximumBytes = 5 * 1_024 * 1_024

  func load(source: String?) async throws -> PackageRegistryIndex {
    let selectedSource = source ?? Self.defaultSource
    let url = try sourceURL(selectedSource)
    let data = try await loadData(from: url)
    let registry: PackageRegistryIndex
    do {
      registry = try JSONDecoder().decode(PackageRegistryIndex.self, from: data)
    } catch {
      throw WidgetPackageError.invalidRegistry(error.localizedDescription)
    }
    guard registry.registryVersion == 1 else {
      throw WidgetPackageError.invalidRegistry("registry_version must be 1")
    }
    guard Set(registry.packages.map(\.name)).count == registry.packages.count else {
      throw WidgetPackageError.invalidRegistry("registry contains duplicate package names")
    }
    try validatePackages(registry.packages)
    return registry
  }

  private func validatePackages(_ packages: [PackageRegistryEntry]) throws {
    for package in packages {
      guard WidgetPackageManifestParser.isPackageName(package.name) else {
        throw WidgetPackageError.invalidRegistry("invalid package name '\(package.name)'")
      }
      guard SemanticVersion(package.latest) != nil else {
        throw WidgetPackageError.invalidRegistry(
          "package '\(package.name)' has invalid latest version '\(package.latest)'"
        )
      }
      guard !package.versions.isEmpty else {
        throw WidgetPackageError.invalidRegistry("package '\(package.name)' has no releases")
      }
      guard Set(package.versions.map(\.version)).count == package.versions.count else {
        throw WidgetPackageError.invalidRegistry(
          "package '\(package.name)' contains duplicate release versions"
        )
      }
      guard package.versions.contains(where: { $0.version == package.latest }) else {
        throw WidgetPackageError.invalidRegistry(
          "package '\(package.name)' latest version is not present in releases"
        )
      }

      for release in package.versions {
        guard SemanticVersion(release.version) != nil else {
          throw WidgetPackageError.invalidRegistry(
            "package '\(package.name)' has invalid release version '\(release.version)'"
          )
        }
        guard
          let archiveURL = URL(string: release.archive),
          ["https", "file"].contains(archiveURL.scheme?.lowercased() ?? "")
        else {
          throw WidgetPackageError.invalidRegistry(
            "package '\(package.name)' release '\(release.version)' has an invalid archive URL"
          )
        }
        guard release.sha256.range(of: "^[0-9A-Fa-f]{64}$", options: .regularExpression) != nil
        else {
          throw WidgetPackageError.invalidRegistry(
            "package '\(package.name)' release '\(release.version)' has an invalid SHA-256"
          )
        }
      }
    }
  }

  private func sourceURL(_ source: String) throws -> URL {
    if let url = URL(string: source), let scheme = url.scheme?.lowercased() {
      guard scheme == "https" || scheme == "file" else {
        throw WidgetPackageError.invalidRegistry("unsupported URL scheme '\(scheme)'")
      }
      return url
    }

    let path = NSString(string: source).expandingTildeInPath
    guard FileManager.default.fileExists(atPath: path) else {
      throw WidgetPackageError.invalidRegistry("source does not exist: \(source)")
    }
    return URL(fileURLWithPath: path)
  }

  private func loadData(from url: URL) async throws -> Data {
    let sourceURL: URL
    if url.isFileURL {
      sourceURL = url
    } else {
      let (downloadedURL, response) = try await URLSession.shared.download(from: url)
      if let response = response as? HTTPURLResponse,
        !(200...299).contains(response.statusCode)
      {
        throw WidgetPackageError.invalidRegistry(
          "\(url.absoluteString) returned HTTP \(response.statusCode)"
        )
      }
      sourceURL = downloadedURL
    }

    let values = try sourceURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
    guard values.isRegularFile == true else {
      throw WidgetPackageError.invalidRegistry("registry source is not a regular file")
    }
    guard let fileSize = values.fileSize, fileSize <= Self.maximumBytes else {
      throw WidgetPackageError.invalidRegistry(
        "registry exceeds the \(Self.maximumBytes)-byte limit"
      )
    }
    return try Data(contentsOf: sourceURL, options: .mappedIfSafe)
  }
}
