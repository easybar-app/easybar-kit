import Foundation

/// Exact or caret constraint used by widget package dependencies.
struct VersionConstraint: CustomStringConvertible, Equatable {
  private enum Kind: Equatable {
    case exact(SemanticVersion)
    case caret(SemanticVersion)
  }

  let rawValue: String
  private let kind: Kind

  init?(_ rawValue: String) {
    guard !rawValue.isEmpty,
      rawValue == rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    else {
      return nil
    }

    if rawValue.hasPrefix("^") {
      guard let minimum = SemanticVersion(String(rawValue.dropFirst())) else { return nil }
      self.rawValue = rawValue
      kind = .caret(minimum)
      return
    }

    guard let exact = SemanticVersion(rawValue) else { return nil }
    self.rawValue = rawValue
    kind = .exact(exact)
  }

  var description: String { rawValue }

  func contains(_ version: SemanticVersion) -> Bool {
    switch kind {
    case .exact(let exact):
      return version == exact
    case .caret(let minimum):
      guard version >= minimum else { return false }
      guard let maximum = Self.caretUpperBound(for: minimum) else { return true }
      return version < maximum
    }
  }

  private static func caretUpperBound(for minimum: SemanticVersion) -> SemanticVersion? {
    if minimum.major > 0 {
      let (major, overflow) = minimum.major.addingReportingOverflow(1)
      return overflow ? nil : SemanticVersion(major: major, minor: 0, patch: 0)
    }

    if minimum.minor > 0 {
      let (minor, overflow) = minimum.minor.addingReportingOverflow(1)
      return overflow ? nil : SemanticVersion(major: 0, minor: minor, patch: 0)
    }

    let (patch, overflow) = minimum.patch.addingReportingOverflow(1)
    return overflow ? nil : SemanticVersion(major: 0, minor: 0, patch: patch)
  }
}
