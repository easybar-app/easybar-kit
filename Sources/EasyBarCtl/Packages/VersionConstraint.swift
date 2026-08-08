import Foundation

struct VersionConstraint: CustomStringConvertible, Equatable {
  let rawValue: String

  init?(_ rawValue: String) {
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    let versionText =
      trimmed.hasPrefix("^")
      ? String(trimmed.dropFirst())
      : String(trimmed.drop(while: { $0 == "=" || $0 == " " }))
    guard !trimmed.isEmpty, SemanticVersion(versionText) != nil else { return nil }
    self.rawValue = trimmed
  }

  var description: String { rawValue }

  func contains(_ version: SemanticVersion) -> Bool {
    if rawValue.hasPrefix("^") {
      guard let minimum = SemanticVersion(String(rawValue.dropFirst())) else { return false }
      let maximum: SemanticVersion
      if minimum.major > 0 {
        maximum = SemanticVersion(major: minimum.major + 1, minor: 0, patch: 0)
      } else if minimum.minor > 0 {
        maximum = SemanticVersion(major: 0, minor: minimum.minor + 1, patch: 0)
      } else {
        maximum = SemanticVersion(major: 0, minor: 0, patch: minimum.patch + 1)
      }
      return version >= minimum && version < maximum
    }

    let exact = rawValue.trimmingCharacters(in: CharacterSet(charactersIn: "= "))
    return SemanticVersion(exact) == version
  }
}
