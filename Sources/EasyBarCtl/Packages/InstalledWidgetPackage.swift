/// Stores installed widget package data.
struct InstalledWidgetPackage: Codable, Equatable {
  /// The name for this installed widget package.
  let name: String
  /// The version for this installed widget package.
  let version: String
  /// The kind for this installed widget package.
  let kind: WidgetPackageKind
  /// The entrypoint for this installed widget package.
  let entrypoint: String?
  /// The dependencies for this installed widget package.
  let dependencies: [String: String]
  /// The exports for this installed widget package.
  let exports: [String: String]
  /// The source for this installed widget package.
  let source: String
}
