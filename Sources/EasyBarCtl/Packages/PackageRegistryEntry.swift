/// Stores package registry entry data.
struct PackageRegistryEntry: Decodable, Equatable {
  /// The name for this package registry entry.
  let name: String
  /// The kind for this package registry entry.
  let kind: WidgetPackageKind
  /// The latest for this package registry entry.
  let latest: String
  /// A human-readable representation of this package registry entry.
  let description: String
  /// The categories for this package registry entry.
  let categories: [String]
  /// The versions for this package registry entry.
  let versions: [PackageRegistryRelease]
}
