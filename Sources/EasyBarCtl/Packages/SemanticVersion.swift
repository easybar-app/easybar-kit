import Foundation

struct SemanticVersion: Comparable, CustomStringConvertible, Equatable, Hashable {
  let major: Int
  let minor: Int
  let patch: Int
  let prerelease: [String]

  init(major: Int, minor: Int, patch: Int, prerelease: [String] = []) {
    self.major = major
    self.minor = minor
    self.patch = patch
    self.prerelease = prerelease
  }

  init?(_ value: String) {
    let versionAndBuild = value.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)
    let versionAndPrerelease = versionAndBuild[0].split(
      separator: "-",
      maxSplits: 1,
      omittingEmptySubsequences: false
    )
    let core = versionAndPrerelease[0].split(separator: ".", omittingEmptySubsequences: false)
    guard core.count == 3,
      let major = Int(core[0]),
      let minor = Int(core[1]),
      let patch = Int(core[2]),
      major >= 0,
      minor >= 0,
      patch >= 0
    else { return nil }

    let prerelease =
      versionAndPrerelease.count == 2
      ? versionAndPrerelease[1].split(separator: ".").map(String.init)
      : []
    guard prerelease.allSatisfy({ !$0.isEmpty }) else { return nil }
    self.major = major
    self.minor = minor
    self.patch = patch
    self.prerelease = prerelease
  }

  var description: String {
    let core = "\(major).\(minor).\(patch)"
    return prerelease.isEmpty ? core : core + "-" + prerelease.joined(separator: ".")
  }

  static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
    if lhs.major != rhs.major { return lhs.major < rhs.major }
    if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
    if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
    if lhs.prerelease.isEmpty { return false }
    if rhs.prerelease.isEmpty { return true }

    for (left, right) in zip(lhs.prerelease, rhs.prerelease) where left != right {
      if let leftNumber = Int(left), let rightNumber = Int(right) {
        return leftNumber < rightNumber
      }
      if Int(left) != nil { return true }
      if Int(right) != nil { return false }
      return left < right
    }
    return lhs.prerelease.count < rhs.prerelease.count
  }
}
