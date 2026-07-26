import Darwin
import EasyBarShared
import Foundation
import SwiftTOMLEdit

/// Applies validated, comment-preserving edits to the active configuration file.
@MainActor
final class ConfigPersistence {
  private enum WriteError: LocalizedError {
    case systemCall(operation: String, code: Int32)

    var errorDescription: String? {
      switch self {
      case .systemCall(let operation, let code):
        return "\(operation) failed: \(String(cString: strerror(code))) (errno=\(code))"
      }
    }
  }

  private static let defaultFilePermissions: mode_t = 0o600

  private let configPath: String
  private let logger: ProcessLogger

  init(configPath: String, logger: ProcessLogger) {
    self.configPath = configPath
    self.logger = logger
  }

  /// Writes one batch atomically after parsing both the input and edited document.
  func apply(_ edits: [TOMLEdit]) -> Bool {
    guard !edits.isEmpty else { return true }
    let url = URL(fileURLWithPath: configPath)

    do {
      let fileExists = FileManager.default.fileExists(atPath: url.path)
      let source: String
      if fileExists {
        source = try String(contentsOf: url, encoding: .utf8)
      } else {
        source = ""
      }

      _ = try TOMLTable(string: source)
      let edited = try TOMLDocument.edit(source, edits: edits)
      _ = try TOMLTable(string: edited)
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try Self.writeAtomically(edited, to: url, replacingExistingFile: fileExists)
      logger.info(
        "persisted config changes",
        .field("path", configPath),
        .field("count", edits.count)
      )
      return true
    } catch {
      logger.error(
        "failed to persist config changes",
        .field("path", configPath),
        .field("error", error.localizedDescription)
      )
      return false
    }
  }

  /// Replaces the config through a same-directory temporary file without widening its mode.
  private static func writeAtomically(
    _ contents: String,
    to url: URL,
    replacingExistingFile: Bool
  ) throws {
    let permissions = try filePermissions(at: url, fileExists: replacingExistingFile)
    var template = Array("\(url.path).tmp.XXXXXX".utf8CString)
    let fileDescriptor = template.withUnsafeMutableBufferPointer { buffer -> Int32 in
      guard let baseAddress = buffer.baseAddress else { return -1 }
      return mkstemp(baseAddress)
    }
    guard fileDescriptor >= 0 else {
      throw WriteError.systemCall(operation: "mkstemp", code: errno)
    }

    let temporaryPath = template.withUnsafeBufferPointer { buffer in
      String(cString: buffer.baseAddress!)
    }
    var shouldRemoveTemporaryFile = true
    defer {
      if shouldRemoveTemporaryFile {
        unlink(temporaryPath)
      }
    }
    defer { close(fileDescriptor) }

    try write(Data(contents.utf8), to: fileDescriptor)

    guard fchmod(fileDescriptor, permissions) == 0 else {
      throw WriteError.systemCall(operation: "fchmod", code: errno)
    }
    guard fsync(fileDescriptor) == 0 else {
      throw WriteError.systemCall(operation: "fsync", code: errno)
    }
    guard rename(temporaryPath, url.path) == 0 else {
      throw WriteError.systemCall(operation: "rename", code: errno)
    }

    shouldRemoveTemporaryFile = false
  }

  /// Preserves an existing config mode and defaults new configs to owner-only access.
  private static func filePermissions(at url: URL, fileExists: Bool) throws -> mode_t {
    guard fileExists else { return defaultFilePermissions }

    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    guard let permissions = attributes[.posixPermissions] as? NSNumber else {
      return defaultFilePermissions
    }
    return mode_t(permissions.uint16Value & 0o777)
  }

  /// Writes all bytes while retrying interrupted system calls.
  private static func write(_ data: Data, to fileDescriptor: Int32) throws {
    try data.withUnsafeBytes { rawBuffer in
      guard let baseAddress = rawBuffer.baseAddress else { return }
      var offset = 0

      while offset < rawBuffer.count {
        let count = Darwin.write(
          fileDescriptor,
          baseAddress.advanced(by: offset),
          rawBuffer.count - offset
        )
        if count > 0 {
          offset += count
          continue
        }
        if count < 0, errno == EINTR {
          continue
        }

        let code = count == 0 ? EIO : errno
        throw WriteError.systemCall(operation: "write", code: code)
      }
    }
  }
}
