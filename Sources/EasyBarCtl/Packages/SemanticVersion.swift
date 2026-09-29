import Foundation

/// Semantic version used for widget package compatibility and release ordering.
struct SemanticVersion: Comparable, CustomStringConvertible, Hashable {
  /// The major for this semantic version.
  let major: Int
  /// The minor for this semantic version.
  let minor: Int
  /// The patch for this semantic version.
  let patch: Int
  /// The prerelease for this semantic version.
  let prerelease: [String]
  /// The build metadata for this semantic version.
  let buildMetadata: [String]

  /// Creates a semantic version.
  init(
    major: Int,
    minor: Int,
    patch: Int,
    prerelease: [String] = [],
    buildMetadata: [String] = []
  ) {
    self.major = major
    self.minor = minor
    self.patch = patch
    self.prerelease = prerelease
    self.buildMetadata = buildMetadata
  }

  /// Parses a semantic version string.
  init?(_ value: String) {
    guard !value.isEmpty, value == value.trimmingCharacters(in: .whitespacesAndNewlines) else {
      return nil
    }

    let versionAndBuild = value.split(
      separator: "+",
      maxSplits: 1,
      omittingEmptySubsequences: false
    )
    guard versionAndBuild.count <= 2 else { return nil }

    let versionAndPrerelease = versionAndBuild[0].split(
      separator: "-",
      maxSplits: 1,
      omittingEmptySubsequences: false
    )
    let core = versionAndPrerelease[0].split(separator: ".", omittingEmptySubsequences: false)
    guard core.count == 3,
      let major = Self.coreNumber(core[0]),
      let minor = Self.coreNumber(core[1]),
      let patch = Self.coreNumber(core[2])
    else {
      return nil
    }

    let prerelease: [String]
    if versionAndPrerelease.count == 2 {
      prerelease = versionAndPrerelease[1].split(
        separator: ".",
        omittingEmptySubsequences: false
      ).map(String.init)
      guard Self.validIdentifiers(prerelease, rejectLeadingZeroNumbers: true) else { return nil }
    } else {
      prerelease = []
    }

    let buildMetadata: [String]
    if versionAndBuild.count == 2 {
      buildMetadata = versionAndBuild[1].split(
        separator: ".",
        omittingEmptySubsequences: false
      ).map(String.init)
      guard Self.validIdentifiers(buildMetadata, rejectLeadingZeroNumbers: false) else {
        return nil
      }
    } else {
      buildMetadata = []
    }

    self.major = major
    self.minor = minor
    self.patch = patch
    self.prerelease = prerelease
    self.buildMetadata = buildMetadata
  }

  /// A human-readable representation of this semantic version.
  var description: String {
    var value = "\(major).\(minor).\(patch)"
    if !prerelease.isEmpty {
      value += "-" + prerelease.joined(separator: ".")
    }
    if !buildMetadata.isEmpty {
      value += "+" + buildMetadata.joined(separator: ".")
    }
    return value
  }

  /// Returns whether two versions have the same precedence and prerelease identifiers.
  static func == (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
    lhs.major == rhs.major
      && lhs.minor == rhs.minor
      && lhs.patch == rhs.patch
      && lhs.prerelease == rhs.prerelease
  }

  /// Feeds this value's components into the supplied hasher.
  func hash(into hasher: inout Hasher) {
    hasher.combine(major)
    hasher.combine(minor)
    hasher.combine(patch)
    hasher.combine(prerelease)
  }

  /// Returns whether the left version has lower semantic-version precedence.
  static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
    if lhs.major != rhs.major { return lhs.major < rhs.major }
    if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
    if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
    if lhs.prerelease.isEmpty { return false }
    if rhs.prerelease.isEmpty { return true }

    for (left, right) in zip(lhs.prerelease, rhs.prerelease) where left != right {
      let leftIsNumeric = Self.isNumericIdentifier(left)
      let rightIsNumeric = Self.isNumericIdentifier(right)

      if leftIsNumeric && rightIsNumeric {
        if left.count != right.count { return left.count < right.count }
        return left < right
      }
      if leftIsNumeric { return true }
      if rightIsNumeric { return false }
      return left < right
    }

    return lhs.prerelease.count < rhs.prerelease.count
  }

  /// Parses a nonnegative core component without forbidden leading zeroes.
  private static func coreNumber(_ value: Substring) -> Int? {
    guard !value.isEmpty, value.allSatisfy(\.isASCIIDigit) else { return nil }
    guard value.count == 1 || value.first != "0" else { return nil }
    return Int(value)
  }

  /// Validates semantic-version prerelease or build identifiers.
  private static func validIdentifiers(
    _ identifiers: [String],
    rejectLeadingZeroNumbers: Bool
  ) -> Bool {
    guard !identifiers.isEmpty else { return false }

    return identifiers.allSatisfy { identifier in
      guard !identifier.isEmpty,
        identifier.allSatisfy({ $0.isASCIILetter || $0.isASCIIDigit || $0 == "-" })
      else {
        return false
      }

      if rejectLeadingZeroNumbers,
        isNumericIdentifier(identifier),
        identifier.count > 1,
        identifier.first == "0"
      {
        return false
      }
      return true
    }
  }

  /// Returns whether an identifier contains only ASCII digits.
  private static func isNumericIdentifier(_ value: String) -> Bool {
    !value.isEmpty && value.allSatisfy(\.isASCIIDigit)
  }
}

extension Character {
  fileprivate var isASCIIDigit: Bool {
    asciiValue.map { (48...57).contains($0) } ?? false
  }

  fileprivate var isASCIILetter: Bool {
    asciiValue.map { (65...90).contains($0) || (97...122).contains($0) } ?? false
  }
}
