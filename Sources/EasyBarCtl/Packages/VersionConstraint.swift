import Foundation

/// Exact or caret constraint used by widget package dependencies.
struct VersionConstraint: CustomStringConvertible, Equatable {
  /// Defines the supported kind values.
  private enum Kind: Equatable {
    case exact(SemanticVersion)
    case caret(SemanticVersion)
  }

  /// The raw serialized value for this version constraint.
  let rawValue: String
  /// The kind for this version constraint.
  private let kind: Kind

  /// Parses an exact or caret semantic-version constraint.
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

  /// A human-readable representation of this version constraint.
  var description: String { rawValue }

  /// Returns whether a version satisfies this constraint.
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

  /// Computes the exclusive upper bound for a caret constraint.
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
