import Foundation

/// Preserves the complete managed package state until a forced replacement succeeds.
final class WidgetPackageReplacementTransaction {
  private let fileManager: FileManager
  private let packagesDirectory: URL
  private let backupDirectory: URL

  private init(
    fileManager: FileManager,
    packagesDirectory: URL,
    backupDirectory: URL
  ) {
    self.fileManager = fileManager
    self.packagesDirectory = packagesDirectory
    self.backupDirectory = backupDirectory
  }

  /// Moves the current state aside and creates a working copy for the replacement attempt.
  static func begin(
    packagesDirectory: URL,
    fileManager: FileManager
  ) throws -> WidgetPackageReplacementTransaction {
    let backupDirectory = siblingDirectory(
      of: packagesDirectory,
      prefix: ".easybar-packages-replacement"
    )
    let transaction = WidgetPackageReplacementTransaction(
      fileManager: fileManager,
      packagesDirectory: packagesDirectory,
      backupDirectory: backupDirectory
    )

    try fileManager.moveItem(at: packagesDirectory, to: backupDirectory)
    do {
      try fileManager.copyItem(at: backupDirectory, to: packagesDirectory)
    } catch {
      try transaction.restoreAfterSetupFailure(originalError: error)
    }
    return transaction
  }

  /// Discards the preserved state after the replacement has been fully materialized.
  func commit() throws {
    try fileManager.removeItem(at: backupDirectory)
  }

  /// Restores the preserved state without first deleting the failed working tree.
  func rollback() throws {
    let failedDirectory = Self.siblingDirectory(
      of: packagesDirectory,
      prefix: ".easybar-packages-failed"
    )
    if fileManager.fileExists(atPath: packagesDirectory.path) {
      try fileManager.moveItem(at: packagesDirectory, to: failedDirectory)
    }

    do {
      try fileManager.moveItem(at: backupDirectory, to: packagesDirectory)
    } catch {
      if fileManager.fileExists(atPath: failedDirectory.path) {
        try? fileManager.moveItem(at: failedDirectory, to: packagesDirectory)
      }
      throw WidgetPackageError.installConflict(
        "forced install failed and the previous package state remains at "
          + "\(backupDirectory.path): \(error.localizedDescription)"
      )
    }

    if fileManager.fileExists(atPath: failedDirectory.path) {
      try fileManager.removeItem(at: failedDirectory)
    }
  }

  private func restoreAfterSetupFailure(originalError: Error) throws -> Never {
    if fileManager.fileExists(atPath: packagesDirectory.path) {
      try? fileManager.removeItem(at: packagesDirectory)
    }
    do {
      try fileManager.moveItem(at: backupDirectory, to: packagesDirectory)
    } catch {
      throw WidgetPackageError.installConflict(
        "could not prepare forced install and the previous package state remains at "
          + "\(backupDirectory.path): \(error.localizedDescription)"
      )
    }
    throw originalError
  }

  private static func siblingDirectory(of directory: URL, prefix: String) -> URL {
    directory.deletingLastPathComponent().appending(
      path: "\(prefix)-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
  }
}
