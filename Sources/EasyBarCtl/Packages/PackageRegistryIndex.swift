/// Stores package registry index data.
struct PackageRegistryIndex: Decodable, Equatable {
  /// The registry version for this package registry index.
  let registryVersion: Int
  /// The packages for this package registry index.
  let packages: [PackageRegistryEntry]

  /// Maps stored properties to their encoded keys.
  private enum CodingKeys: String, CodingKey {
    case registryVersion = "registry_version"
    case packages
  }
}
