import EasyBarShared

/// Stores installed widget packages data.
struct InstalledWidgetPackages: Codable, Equatable {
  /// The layout version for this installed widget packages.
  let layoutVersion: Int
  /// The packages for this installed widget packages.
  var packages: [InstalledWidgetPackage]

  /// The empty for this installed widget packages.
  static let empty = InstalledWidgetPackages(
    layoutVersion: WidgetPackageStore.layoutVersion,
    packages: []
  )

  /// Maps stored properties to their encoded keys.
  private enum CodingKeys: String, CodingKey {
    case layoutVersion = "layout_version"
    case packages
  }
}
