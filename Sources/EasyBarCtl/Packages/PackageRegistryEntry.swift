struct PackageRegistryEntry: Decodable, Equatable {
  let name: String
  let latest: String
  let versions: [PackageRegistryRelease]
}
