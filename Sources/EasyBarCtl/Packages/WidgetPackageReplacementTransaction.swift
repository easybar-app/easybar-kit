import Foundation

/// Tracks package-local filesystem replacements so a failed install can restore prior paths.
final class WidgetPackageReplacementTransaction {
  private struct Change {
    let destination: URL
    let backup: URL?
    let installedReplacement: Bool
  }

  private let fileManager: FileManager
  private let identifier = UUID().uuidString
  private var changes: [Change] = []

  init(fileManager: FileManager) {
    self.fileManager = fileManager
  }

  /// Replaces one path with a prepared item while retaining the previous item as a backup.
  func replaceItem(at destination: URL, with preparedItem: URL) throws {
    try fileManager.createDirectory(
      at: destination.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )

    let backup = itemExists(destination) ? backupURL(for: destination) : nil
    if let backup {
      try fileManager.moveItem(at: destination, to: backup)
    }

    do {
      try fileManager.moveItem(at: preparedItem, to: destination)
    } catch {
      if let backup {
        try? fileManager.moveItem(at: backup, to: destination)
      }
      throw error
    }

    changes.append(
      Change(
        destination: destination,
        backup: backup,
        installedReplacement: true
      )
    )
  }

  /// Replaces one path with a relative symbolic link to a committed store item.
  func replaceWithSymbolicLink(at destination: URL, to target: URL) throws {
    try fileManager.createDirectory(
      at: destination.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )

    let staged = stagingURL(for: destination)
    let relativeTarget = relativePath(
      from: destination.deletingLastPathComponent(),
      to: target
    )
    try fileManager.createSymbolicLink(
      atPath: staged.path,
      withDestinationPath: relativeTarget
    )

    do {
      try replaceItem(at: destination, with: staged)
    } catch {
      try? fileManager.removeItem(at: staged)
      throw error
    }
  }

  /// Removes one path transactionally, retaining it until the install commits.
  func removeItem(at destination: URL) throws {
    guard itemExists(destination) else { return }
    let backup = backupURL(for: destination)
    try fileManager.moveItem(at: destination, to: backup)
    changes.append(
      Change(
        destination: destination,
        backup: backup,
        installedReplacement: false
      )
    )
  }

  /// Discards backups after the package database has been committed successfully.
  func commit() {
    for change in changes {
      if let backup = change.backup, itemExists(backup) {
        try? fileManager.removeItem(at: backup)
      }
    }
    changes.removeAll()
  }

  /// Restores every replaced path in reverse order.
  func rollback() throws {
    var firstFailure: Error?

    for change in changes.reversed() {
      do {
        if change.installedReplacement, itemExists(change.destination) {
          try fileManager.removeItem(at: change.destination)
        }
        if let backup = change.backup, itemExists(backup) {
          try fileManager.moveItem(at: backup, to: change.destination)
        }
      } catch {
        if firstFailure == nil {
          firstFailure = error
        }
      }
    }

    changes.removeAll()
    if let firstFailure {
      throw firstFailure
    }
  }

  private func backupURL(for destination: URL) -> URL {
    destination.deletingLastPathComponent().appending(
      path: "\(destination.lastPathComponent).backup-\(identifier)",
      directoryHint: destination.hasDirectoryPath ? .isDirectory : .notDirectory
    )
  }

  private func stagingURL(for destination: URL) -> URL {
    destination.deletingLastPathComponent().appending(
      path: "\(destination.lastPathComponent).staging-\(identifier)",
      directoryHint: .notDirectory
    )
  }

  private func itemExists(_ url: URL) -> Bool {
    fileManager.fileExists(atPath: url.path)
      || (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) != nil
  }

  private func relativePath(from directory: URL, to target: URL) -> String {
    let sourceComponents = directory.standardizedFileURL.pathComponents
    let targetComponents = target.standardizedFileURL.pathComponents
    var common = 0

    while common < sourceComponents.count,
      common < targetComponents.count,
      sourceComponents[common] == targetComponents[common]
    {
      common += 1
    }

    let parents = Array(repeating: "..", count: sourceComponents.count - common)
    let descendants = Array(targetComponents.dropFirst(common))
    let components = parents + descendants
    return components.isEmpty ? "." : components.joined(separator: "/")
  }
}
