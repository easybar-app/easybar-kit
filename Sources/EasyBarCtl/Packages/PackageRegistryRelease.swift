/// Stores package registry release data.
struct PackageRegistryRelease: Decodable, Equatable {
  /// The version for this package registry release.
  let version: String
  /// The archive for this package registry release.
  let archive: String
  /// The SHA-256 for this package registry release.
  let sha256: String
}
