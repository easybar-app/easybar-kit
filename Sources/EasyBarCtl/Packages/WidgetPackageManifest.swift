struct WidgetPackageManifest: Equatable {
  let name: String
  let version: SemanticVersion
  let minimumEasyBarKitVersion: SemanticVersion
  let kind: WidgetPackageKind
  let entrypoint: String?
  let dependencies: [String: VersionConstraint]
  let exports: [String: String]
}
