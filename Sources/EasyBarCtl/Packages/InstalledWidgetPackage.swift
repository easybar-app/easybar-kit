struct InstalledWidgetPackage: Codable, Equatable {
  let name: String
  let version: String
  let kind: WidgetPackageKind
  let entrypoint: String?
  let dependencies: [String: String]
  let exports: [String: String]
  let source: String
}
