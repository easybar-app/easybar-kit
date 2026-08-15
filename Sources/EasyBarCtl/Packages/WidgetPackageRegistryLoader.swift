import CryptoKit
import Foundation

struct WidgetPackageRegistryLoader {
  static let defaultSource =
    "https://raw.githubusercontent.com/easybar-app/registry/main/index.json"
  private static let maximumBytes = 5 * 1_024 * 1_024
  private static let defaultCacheDirectory = FileManager.default.homeDirectoryForCurrentUser
    .appending(path: ".cache/easybar/registry", directoryHint: .isDirectory)

  private struct CacheMetadata: Codable {
    let source: String
    let eTag: String?
    let lastModified: String?
    let sha256: String
  }

  private struct CachedRegistry {
    let data: Data
    let metadata: CacheMetadata
  }

  private enum RemoteLoadResult {
    case modified(data: Data, metadata: CacheMetadata)
    case notModified
  }

  private let session: URLSession
  private let fileManager: FileManager
  private let cacheDirectory: URL

  init(
    session: URLSession = .shared,
    fileManager: FileManager = .default,
    cacheDirectory: URL = Self.defaultCacheDirectory
  ) {
    self.session = session
    self.fileManager = fileManager
    self.cacheDirectory = cacheDirectory
  }

  func load(
    source: String?,
    refresh: Bool = false
  ) async throws -> PackageRegistryIndex {
    let selectedSource = source ?? Self.defaultSource
    let url = try sourceURL(selectedSource)

    if url.isFileURL {
      return try decodeRegistry(try loadFileData(from: url))
    }

    if refresh {
      return try await loadRemoteWithoutValidators(from: url, source: selectedSource)
    }

    let cached = cachedRegistry(for: selectedSource)
    let result = try await loadRemoteData(
      from: url,
      source: selectedSource,
      validators: cached?.metadata
    )

    switch result {
    case .modified(let data, let metadata):
      let registry = try decodeRegistry(data)
      storeCache(data: data, metadata: metadata)
      return registry

    case .notModified:
      guard let cached else {
        return try await loadRemoteWithoutValidators(from: url, source: selectedSource)
      }

      do {
        return try decodeRegistry(cached.data)
      } catch {
        return try await loadRemoteWithoutValidators(from: url, source: selectedSource)
      }
    }
  }

  private func loadRemoteWithoutValidators(
    from url: URL,
    source: String
  ) async throws -> PackageRegistryIndex {
    let result = try await loadRemoteData(from: url, source: source, validators: nil)
    guard case .modified(let data, let metadata) = result else {
      throw WidgetPackageError.invalidRegistry(
        "\(url.absoluteString) returned HTTP 304 without a usable cached registry"
      )
    }
    let registry = try decodeRegistry(data)
    storeCache(data: data, metadata: metadata)
    return registry
  }

  private func decodeRegistry(_ data: Data) throws -> PackageRegistryIndex {
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
    guard fileManager.fileExists(atPath: path) else {
      throw WidgetPackageError.invalidRegistry("source does not exist: \(source)")
    }
    return URL(fileURLWithPath: path)
  }

  private func loadFileData(from url: URL) throws -> Data {
    let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
    guard values.isRegularFile == true else {
      throw WidgetPackageError.invalidRegistry("registry source is not a regular file")
    }
    guard let fileSize = values.fileSize, fileSize <= Self.maximumBytes else {
      throw WidgetPackageError.invalidRegistry(
        "registry exceeds the \(Self.maximumBytes)-byte limit"
      )
    }
    return try Data(contentsOf: url, options: .mappedIfSafe)
  }

  private func loadRemoteData(
    from url: URL,
    source: String,
    validators: CacheMetadata?
  ) async throws -> RemoteLoadResult {
    var request = URLRequest(
      url: url,
      cachePolicy: .reloadIgnoringLocalCacheData,
      timeoutInterval: 30
    )
    request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
    if let eTag = validators?.eTag {
      request.setValue(eTag, forHTTPHeaderField: "If-None-Match")
    }
    if let lastModified = validators?.lastModified {
      request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
    }

    let (data, response) = try await session.data(for: request)
    guard let response = response as? HTTPURLResponse else {
      throw WidgetPackageError.invalidRegistry("registry source did not return an HTTP response")
    }

    if response.statusCode == 304 {
      return .notModified
    }

    guard (200...299).contains(response.statusCode) else {
      throw WidgetPackageError.invalidRegistry(
        "\(url.absoluteString) returned HTTP \(response.statusCode)"
      )
    }
    guard data.count <= Self.maximumBytes else {
      throw WidgetPackageError.invalidRegistry(
        "registry exceeds the \(Self.maximumBytes)-byte limit"
      )
    }

    return .modified(
      data: data,
      metadata: CacheMetadata(
        source: source,
        eTag: response.value(forHTTPHeaderField: "ETag"),
        lastModified: response.value(forHTTPHeaderField: "Last-Modified"),
        sha256: sha256(data)
      )
    )
  }

  private func cachedRegistry(for source: String) -> CachedRegistry? {
    let paths = cachePaths(for: source)
    guard
      let metadataData = try? Data(contentsOf: paths.metadata),
      let metadata = try? JSONDecoder().decode(CacheMetadata.self, from: metadataData),
      metadata.source == source,
      let values = try? paths.index.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
      values.isRegularFile == true,
      let fileSize = values.fileSize,
      fileSize <= Self.maximumBytes,
      let data = try? Data(contentsOf: paths.index, options: .mappedIfSafe),
      sha256(data) == metadata.sha256
    else {
      return nil
    }
    return CachedRegistry(data: data, metadata: metadata)
  }

  private func storeCache(data: Data, metadata: CacheMetadata) {
    let paths = cachePaths(for: metadata.source)
    do {
      try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      var metadataData = try encoder.encode(metadata)
      metadataData.append(0x0A)
      try data.write(to: paths.index, options: .atomic)
      try metadataData.write(to: paths.metadata, options: .atomic)
    } catch {
      // Registry caching is an optimization. A cache write must never block package operations.
    }
  }

  private func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private func cachePaths(for source: String) -> (index: URL, metadata: URL) {
    let digest = sha256(Data(source.utf8))
    return (
      cacheDirectory.appending(path: "\(digest).json"),
      cacheDirectory.appending(path: "\(digest).metadata.json")
    )
  }
}
