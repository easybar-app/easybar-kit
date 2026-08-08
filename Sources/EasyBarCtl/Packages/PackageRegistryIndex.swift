struct PackageRegistryIndex: Decodable, Equatable {
  let registryVersion: Int
  let packages: [PackageRegistryEntry]

  private enum CodingKeys: String, CodingKey {
    case registryVersion = "registry_version"
    case packages
  }
}
