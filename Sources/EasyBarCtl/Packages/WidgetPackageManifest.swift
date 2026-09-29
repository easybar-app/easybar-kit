/// Stores widget package manifest data.
struct WidgetPackageManifest: Equatable {
  /// The name for this widget package manifest.
  let name: String
  /// The version for this widget package manifest.
  let version: SemanticVersion
  /// The minimum EasyBarKit version accepted by this widget package manifest.
  let minimumEasyBarKitVersion: SemanticVersion
  /// The kind for this widget package manifest.
  let kind: WidgetPackageKind
  /// The entrypoint for this widget package manifest.
  let entrypoint: String?
  /// The dependencies for this widget package manifest.
  let dependencies: [String: VersionConstraint]
  /// The exports for this widget package manifest.
  let exports: [String: String]
}
