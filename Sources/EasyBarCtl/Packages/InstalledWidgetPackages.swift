struct InstalledWidgetPackages: Codable, Equatable {
  let layoutVersion: Int
  var packages: [InstalledWidgetPackage]

  static let empty = InstalledWidgetPackages(layoutVersion: 1, packages: [])

  private enum CodingKeys: String, CodingKey {
    case layoutVersion = "layout_version"
    case packages
  }
}
