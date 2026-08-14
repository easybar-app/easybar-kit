import CryptoKit
import EasyBarShared
import Foundation

private enum WidgetPackageRequest {
  case registry(name: String, constraint: VersionConstraint?)
  case directory(URL)
  case archive(URL, sha256: String?, remote: Bool)
}

final class WidgetPackageResolver {
  static let defaultRegistry = WidgetPackageRegistryLoader.defaultSource
  private static let maximumArchiveBytes = 20 * 1_024 * 1_024

  private let registrySource: String?
  private let useRegistry: Bool
  private let temporaryDirectory: URL
  private let processExecutor: ProcessExecutor
  private var registry: PackageRegistryIndex?
  private var resolved: [String: ResolvedWidgetPackage] = [:]
  private var resolutionOrder: [String] = []
  private var resolving: [String] = []
  private let installed: [String: InstalledWidgetPackage]
  private let currentKitVersion: SemanticVersion?

  init(
    registrySource: String?,
    useRegistry: Bool,
    temporaryDirectory: URL,
    installed: [InstalledWidgetPackage],
    logger: ProcessLogger,
    currentKitVersion: SemanticVersion? = SemanticVersion(BuildInfo.appVersion)
  ) {
    self.registrySource = registrySource
    self.useRegistry = useRegistry
    self.temporaryDirectory = temporaryDirectory
    self.installed = Dictionary(uniqueKeysWithValues: installed.map { ($0.name, $0) })
    self.currentKitVersion = currentKitVersion
    processExecutor = ProcessExecutor(logger: logger.child("archive"))
  }

  func resolve(source: String, sha256: String?) async throws -> [ResolvedWidgetPackage] {
    let request = try rootRequest(source: source, sha256: sha256)
    _ = try await resolve(request, requiredBy: nil)
    return resolutionOrder.compactMap { resolved[$0] }
  }

  private func resolve(
    _ request: WidgetPackageRequest,
    requiredBy parent: WidgetPackageManifest?
  ) async throws -> ResolvedWidgetPackage {
    let expectedName: String?
    let constraint: VersionConstraint?
    switch request {
    case .registry(let name, let requestedConstraint):
      expectedName = name
      constraint = requestedConstraint
    case .directory, .archive:
      expectedName = nil
      constraint = nil
    }

    if let expectedName, let existing = resolved[expectedName] {
      if let constraint, !constraint.contains(existing.manifest.version), let parent {
        throw WidgetPackageError.incompatibleDependency(
          package: parent.name,
          dependency: expectedName,
          constraint: constraint.rawValue
        )
      }
      return existing
    }

    let package = try await load(request)
    try validateKitCompatibility(package.manifest)
    if let expectedName, package.manifest.name != expectedName {
      throw WidgetPackageError.invalidManifest(
        "expected package '\(expectedName)', archive contains '\(package.manifest.name)'"
      )
    }
    if let constraint, !constraint.contains(package.manifest.version), let parent {
      throw WidgetPackageError.incompatibleDependency(
        package: parent.name,
        dependency: package.manifest.name,
        constraint: constraint.rawValue
      )
    }
    if resolving.contains(package.manifest.name) {
      throw WidgetPackageError.invalidManifest(
        "dependency cycle: \((resolving + [package.manifest.name]).joined(separator: " -> "))"
      )
    }
    resolving.append(package.manifest.name)
    defer { resolving.removeLast() }

    for (dependency, dependencyConstraint) in package.manifest.dependencies.sorted(by: {
      $0.key < $1.key
    }) {
      if let staged = resolved[dependency], dependencyConstraint.contains(staged.manifest.version) {
        continue
      }
      if let current = installed[dependency],
        let version = SemanticVersion(current.version),
        dependencyConstraint.contains(version)
      {
        continue
      }
      guard useRegistry else {
        throw WidgetPackageError.unavailableDependency(
          package: package.manifest.name,
          dependency: dependency,
          constraint: dependencyConstraint.rawValue
        )
      }
      _ = try await resolve(
        .registry(name: dependency, constraint: dependencyConstraint),
        requiredBy: package.manifest
      )
    }

    resolved[package.manifest.name] = package
    resolutionOrder.append(package.manifest.name)
    return package
  }

  private func validateKitCompatibility(_ manifest: WidgetPackageManifest) throws {
    guard let currentKitVersion else { return }
    guard currentKitVersion >= manifest.minimumEasyBarKitVersion else {
      throw WidgetPackageError.incompatibleKitVersion(
        package: manifest.name,
        minimum: manifest.minimumEasyBarKitVersion.description,
        current: currentKitVersion.description
      )
    }
  }

  private func rootRequest(source: String, sha256: String?) throws -> WidgetPackageRequest {
    if let url = URL(string: source), let scheme = url.scheme?.lowercased() {
      switch scheme {
      case "https":
        return .archive(url, sha256: sha256, remote: true)
      case "file":
        return .archive(url, sha256: sha256, remote: false)
      default:
        throw WidgetPackageError.invalidSource("unsupported URL scheme '\(scheme)'")
      }
    }

    let expanded = NSString(string: source).expandingTildeInPath
    return try localRequest(path: expanded, sha256: sha256, originalSource: source)
  }

  private func localRequest(
    path: String,
    sha256: String?,
    originalSource: String? = nil
  ) throws -> WidgetPackageRequest {
    let expanded = NSString(string: path).expandingTildeInPath
    var isDirectory: ObjCBool = false
    if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory) {
      let url = URL(fileURLWithPath: expanded, isDirectory: isDirectory.boolValue)
      if isDirectory.boolValue {
        guard sha256 == nil else {
          throw WidgetPackageError.invalidSource("--sha256 cannot be used with a directory")
        }
        return .directory(url)
      }
      return .archive(url, sha256: sha256, remote: false)
    }

    let source = originalSource ?? path
    guard originalSource != nil, let specifier = try registrySpecifier(source) else {
      throw WidgetPackageError.invalidSource("path does not exist: \(source)")
    }
    guard useRegistry else {
      throw WidgetPackageError.invalidSource(
        "registry package names require a registry; provide a local path or HTTPS archive URL"
      )
    }
    guard sha256 == nil else {
      throw WidgetPackageError.invalidSource("--sha256 is only valid for direct archives")
    }
    return .registry(name: specifier.name, constraint: specifier.constraint)
  }

  private func registrySpecifier(
    _ source: String
  ) throws -> (name: String, constraint: VersionConstraint?)? {
    if WidgetPackageManifestParser.isPackageName(source) {
      return (source, nil)
    }

    let components = source.split(separator: "@", omittingEmptySubsequences: false)
    guard components.count > 1 else { return nil }

    let name = String(components[0])
    guard WidgetPackageManifestParser.isPackageName(name) else { return nil }
    guard components.count == 2 else {
      throw WidgetPackageError.invalidSource("invalid registry package selector '\(source)'")
    }

    let version = String(components[1])
    guard let constraint = VersionConstraint(version) else {
      throw WidgetPackageError.invalidSource("invalid package version '\(version)'")
    }
    return (name, constraint)
  }

  private func load(_ request: WidgetPackageRequest) async throws -> ResolvedWidgetPackage {
    switch request {
    case .directory(let directory):
      try rejectSymbolicLinks(in: directory)
      return ResolvedWidgetPackage(
        manifest: try WidgetPackageManifestParser.parse(directory: directory),
        directory: directory,
        source: directory.path
      )

    case .archive(let archive, let digest, let remote):
      if remoteArchiveRequiresChecksum(remote: remote, digest: digest) {
        throw WidgetPackageError.checksumRequired(archive.absoluteString)
      }
      return try await loadArchive(url: archive, expectedSHA256: digest)

    case .registry(let name, let constraint):
      let index = try await registryIndex()
      guard let entry = index.packages.first(where: { $0.name == name }) else {
        throw WidgetPackageError.unavailablePackage(name)
      }
      let releases = entry.versions.compactMap {
        release -> (PackageRegistryRelease, SemanticVersion)? in
        guard let version = SemanticVersion(release.version),
          constraint?.contains(version) ?? (release.version == entry.latest)
        else { return nil }
        return (release, version)
      }
      guard let release = releases.max(by: { $0.1 < $1.1 })?.0 else {
        if resolving.isEmpty, let constraint {
          throw WidgetPackageError.unavailablePackageVersion(
            package: name,
            version: constraint.rawValue
          )
        }
        throw WidgetPackageError.unavailableDependency(
          package: resolving.last ?? name,
          dependency: name,
          constraint: constraint?.rawValue ?? entry.latest
        )
      }
      guard let url = URL(string: release.archive),
        ["https", "file"].contains(url.scheme?.lowercased() ?? "")
      else {
        throw WidgetPackageError.invalidRegistry(
          "package '\(name)' release '\(release.version)' has an invalid archive URL"
        )
      }
      return try await loadArchive(url: url, expectedSHA256: release.sha256)
    }
  }

  private func registryIndex() async throws -> PackageRegistryIndex {
    if let registry { return registry }
    let decoded = try await WidgetPackageRegistryLoader().load(source: registrySource)
    registry = decoded
    return decoded
  }

  private func loadArchive(
    url: URL,
    expectedSHA256: String?
  ) async throws -> ResolvedWidgetPackage {
    let data = try await loadData(from: url, maximumBytes: Self.maximumArchiveBytes)
    let actualDigest = SHA256.hash(data: data).map { byte in
      let hexadecimal = String(byte, radix: 16)
      return hexadecimal.count == 1 ? "0" + hexadecimal : hexadecimal
    }.joined()
    if let expectedSHA256 {
      let normalized = expectedSHA256.lowercased()
      guard normalized.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else {
        throw WidgetPackageError.invalidSource("SHA-256 must contain 64 hexadecimal characters")
      }
      guard normalized == actualDigest else {
        throw WidgetPackageError.checksumMismatch(expected: normalized, actual: actualDigest)
      }
    }

    let staging = temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
    let archive = staging.appending(path: "package.tar.gz")
    let extracted = staging.appending(path: "contents", directoryHint: .isDirectory)
    try data.write(to: archive, options: .atomic)
    try FileManager.default.createDirectory(at: extracted, withIntermediateDirectories: true)
    try await validateArchiveEntries(archive)
    _ = try await runTar(["-xzf", archive.path, "-C", extracted.path])
    try rejectSymbolicLinks(in: extracted)
    let manifest = try WidgetPackageManifestParser.parse(directory: extracted)
    return ResolvedWidgetPackage(
      manifest: manifest,
      directory: extracted,
      source: url.absoluteString
    )
  }

  private func validateArchiveEntries(_ archive: URL) async throws {
    let output = try await runTar(["-tzf", archive.path])
    let entries = output.split(whereSeparator: \.isNewline).map(String.init)
    guard entries.contains("package.toml") else {
      throw WidgetPackageError.unsafeArchive("package.toml must be at the archive root")
    }
    for entry in entries {
      if archiveEntryEscapesPackageRoot(entry) {
        throw WidgetPackageError.unsafeArchive("entry escapes the package root: \(entry)")
      }
    }

    let verbose = try await runTar(["-tvzf", archive.path])
    for line in verbose.split(whereSeparator: \.isNewline) {
      guard line.first == "-" || line.first == "d" else {
        throw WidgetPackageError.unsafeArchive("links and special files are not allowed")
      }
    }
  }

  private func archiveEntryEscapesPackageRoot(_ entry: String) -> Bool {
    entry.hasPrefix("/") || URL(fileURLWithPath: entry).pathComponents.contains("..")
  }

  private func remoteArchiveRequiresChecksum(remote: Bool, digest: String?) -> Bool {
    remote && digest == nil
  }

  private func runTar(_ arguments: [String]) async throws -> String {
    let result = try await processExecutor.run(
      ProcessExecutionRequest(
        executablePath: "/usr/bin/tar",
        arguments: ["/usr/bin/tar"] + arguments,
        environment: SharedPathDefaults.defaultLuaEnvironment.merging(["LC_ALL": "C"]) {
          current, _ in current
        },
        timeout: 30,
        standardOutputLimit: 1_024 * 1_024,
        standardErrorLimit: 64 * 1_024
      )
    )
    guard result.outcome == .completed, result.termination.shellExitStatus == 0 else {
      let error = String(data: result.standardError, encoding: .utf8) ?? "unknown tar error"
      throw WidgetPackageError.commandFailed("could not extract package archive: \(error)")
    }
    return String(data: result.standardOutput, encoding: .utf8) ?? ""
  }

  private func loadData(from url: URL, maximumBytes: Int) async throws -> Data {
    let sourceURL: URL
    if url.isFileURL {
      sourceURL = url
    } else {
      let (downloadedURL, response) = try await URLSession.shared.download(from: url)
      if let response = response as? HTTPURLResponse,
        !(200...299).contains(response.statusCode)
      {
        throw WidgetPackageError.invalidSource(
          "\(url.absoluteString) returned HTTP \(response.statusCode)"
        )
      }
      sourceURL = downloadedURL
    }

    let values = try sourceURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
    guard values.isRegularFile == true else {
      throw WidgetPackageError.invalidSource("archive is not a regular file: \(url.absoluteString)")
    }
    guard let fileSize = values.fileSize, fileSize <= maximumBytes else {
      throw WidgetPackageError.archiveTooLarge(maximumBytes)
    }
    return try Data(contentsOf: sourceURL, options: .mappedIfSafe)
  }

  private func rejectSymbolicLinks(in directory: URL) throws {
    guard
      let enumerator = FileManager.default.enumerator(
        at: directory,
        includingPropertiesForKeys: [.isSymbolicLinkKey],
        options: []
      )
    else {
      throw WidgetPackageError.invalidSource("could not enumerate \(directory.path)")
    }
    for case let url as URL in enumerator {
      if try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
        throw WidgetPackageError.unsafeArchive(
          "symbolic links are not allowed: \(url.lastPathComponent)")
      }
    }
  }
}
