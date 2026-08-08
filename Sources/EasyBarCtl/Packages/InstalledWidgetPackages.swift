import EasyBarShared

struct InstalledWidgetPackages: Codable, Equatable {
  let layoutVersion: Int
  var packages: [InstalledWidgetPackage]

  static let empty = InstalledWidgetPackages(
    layoutVersion: WidgetPackageStore.layoutVersion,
    packages: []
  )

  private enum CodingKeys: String, CodingKey {
    case layoutVersion = "layout_version"
    case packages
  }
}
