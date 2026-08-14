import Foundation

enum WidgetPackageError: LocalizedError, Equatable {
  case invalidSource(String)
  case invalidManifest(String)
  case invalidRegistry(String)
  case unavailablePackage(String)
  case unavailablePackageVersion(package: String, version: String)
  case packageAlreadyInstalled(String)
  case packageNotInstalled(String)
  case packageNotManagedByRegistry(String)
  case packageRequired(name: String, dependents: [String])
  case unavailableDependency(package: String, dependency: String, constraint: String)
  case incompatibleDependency(package: String, dependency: String, constraint: String)
  case incompatibleKitVersion(package: String, minimum: String, current: String)
  case checksumRequired(String)
  case checksumMismatch(expected: String, actual: String)
  case archiveTooLarge(Int)
  case unsafeArchive(String)
  case commandFailed(String)
  case installConflict(String)

  var errorDescription: String? {
    switch self {
    case .invalidSource(let message):
      "invalid package source: \(message)"
    case .invalidManifest(let message):
      "invalid package manifest: \(message)"
    case .invalidRegistry(let message):
      "invalid package registry: \(message)"
    case .unavailablePackage(let name):
      "package '\(name)' was not found in the registry"
    case .unavailablePackageVersion(let package, let version):
      "package '\(package)' version '\(version)' was not found in the registry"
    case .packageAlreadyInstalled(let name):
      "package '\(name)' is already installed; use --force to replace it"
    case .packageNotInstalled(let name):
      "package '\(name)' is not installed"
    case .packageNotManagedByRegistry(let name):
      "package '\(name)' was not installed from the selected registry"
    case .packageRequired(let name, let dependents):
      "package '\(name)' is required by: \(dependents.joined(separator: ", "))"
    case .unavailableDependency(let package, let dependency, let constraint):
      "package '\(package)' requires \(dependency) \(constraint); install that dependency directly or enable a registry"
    case .incompatibleDependency(let package, let dependency, let constraint):
      "package '\(package)' requires \(dependency) \(constraint), but the selected version is incompatible"
    case .incompatibleKitVersion(let package, let minimum, let current):
      "package '\(package)' requires EasyBarKit \(minimum) or newer, but this build provides \(current)"
    case .checksumRequired(let source):
      "a SHA-256 is required for direct remote archive \(source)"
    case .checksumMismatch(let expected, let actual):
      "archive checksum mismatch: expected \(expected), got \(actual)"
    case .archiveTooLarge(let maximum):
      "package archive exceeds the \(maximum)-byte limit"
    case .unsafeArchive(let message):
      "unsafe package archive: \(message)"
    case .commandFailed(let message):
      message
    case .installConflict(let message):
      "package install conflict: \(message)"
    }
  }
}
