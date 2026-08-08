struct PackageRegistryEntry: Decodable, Equatable {
  let name: String
  let kind: WidgetPackageKind
  let latest: String
  let description: String
  let categories: [String]
  let versions: [PackageRegistryRelease]
}
