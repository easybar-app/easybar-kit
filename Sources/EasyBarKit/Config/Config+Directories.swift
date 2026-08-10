import Foundation

extension Config {

  /// One resolved filesystem requirement for the runtime.
  struct RequiredDirectory: Sendable {
    /// Filesystem requirement kind.
    enum Kind: Sendable {
      /// The configured path must exist as a directory, creating it when missing.
      case directory
      /// The configured path may be absent, but must be a directory when it exists.
      case optionalDirectory
      /// The configured path is a file and its parent must exist.
      case parentDirectory
    }

    /// Config key that registered this requirement.
    let configPath: String
    /// Filesystem path to validate or create.
    let path: String
    /// Requirement behavior for the path.
    let kind: Kind
  }

  /// Removes all currently registered directory requirements.
  func resetRegisteredDirectories() {
    registeredDirectories.removeAll()
  }

  /// Registers or replaces one runtime filesystem requirement.
  ///
  /// The registry is keyed by config path so later values for the same config
  /// field replace earlier ones cleanly within the same load cycle.
  func registerDirectoryRequirement(
    for configPath: String,
    path: String,
    kind: RequiredDirectory.Kind
  ) {
    registeredDirectories[configPath] = RequiredDirectory(
      configPath: configPath,
      path: path,
      kind: kind
    )
  }

  /// Creates required directories and validates optional directory paths.
  func ensureRequiredDirectoriesExist() throws {
    for requiredDirectory in registeredDirectories.values.sorted(by: {
      $0.configPath < $1.configPath
    }) {
      switch requiredDirectory.kind {
      case .directory:
        try ensureDirectoryExists(
          at: requiredDirectory.path,
          path: requiredDirectory.configPath,
          createIfMissing: true
        )

      case .optionalDirectory:
        try ensureDirectoryExists(
          at: requiredDirectory.path,
          path: requiredDirectory.configPath,
          createIfMissing: false
        )

      case .parentDirectory:
        try ensureParentDirectoryExists(
          forFileAt: requiredDirectory.path,
          path: requiredDirectory.configPath
        )
      }
    }
  }

  /// Validates one configured directory and optionally creates it when missing.
  private func ensureDirectoryExists(
    at pathValue: String,
    path: String,
    createIfMissing: Bool
  ) throws {
    let trimmedPath = pathValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedPath.isEmpty else { return }

    let expandedPath = NSString(string: trimmedPath).expandingTildeInPath
    let url = URL(fileURLWithPath: expandedPath, isDirectory: true)

    var isDirectory: ObjCBool = false
    let exists = FileManager.default.fileExists(
      atPath: url.path,
      isDirectory: &isDirectory
    )

    if exists {
      guard isDirectory.boolValue else {
        throw ConfigError.invalidValue(
          path: path,
          message: "expected directory path, but found file at \(url.path)"
        )
      }
      return
    }

    guard createIfMissing else { return }

    do {
      try FileManager.default.createDirectory(
        at: url,
        withIntermediateDirectories: true
      )
    } catch {
      throw ConfigError.invalidValue(
        path: path,
        message: "failed to create directory at \(url.path): \(error)"
      )
    }
  }

  /// Creates the parent directory for one configured file path when needed.
  private func ensureParentDirectoryExists(
    forFileAt pathValue: String,
    path: String
  ) throws {
    let trimmedPath = pathValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedPath.isEmpty else { return }

    let expandedPath = NSString(string: trimmedPath).expandingTildeInPath
    let fileURL = URL(fileURLWithPath: expandedPath)
    let parentURL = fileURL.deletingLastPathComponent()

    try ensureDirectoryExists(
      at: parentURL.path,
      path: path,
      createIfMissing: true
    )
  }
}
