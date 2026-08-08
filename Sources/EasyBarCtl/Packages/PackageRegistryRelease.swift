struct PackageRegistryRelease: Decodable, Equatable {
  let version: String
  let archive: String
  let sha256: String
}
