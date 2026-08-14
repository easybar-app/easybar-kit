import Foundation

private struct WidgetPackagePins: Codable, Equatable {
  let layoutVersion: Int
  var packages: [String]

  private enum CodingKeys: String, CodingKey {
    case layoutVersion = "layout_version"
    case packages
  }
}

struct WidgetPackagePinStore {
  static let layoutVersion = 1

  private let fileManager: FileManager

  init(fileManager: FileManager = .default) {
    self.fileManager = fileManager
  }

  func load(from packagesDirectory: URL) throws -> Set<String> {
    let url = packagesDirectory.appending(path: "pins.json")
    guard fileManager.fileExists(atPath: url.path) else { return [] }

    let state: WidgetPackagePins
    do {
      state = try JSONDecoder().decode(
        WidgetPackagePins.self,
        from: Data(contentsOf: url)
      )
    } catch {
      throw WidgetPackageError.installConflict(
        "could not read package pins at \(url.path): \(error.localizedDescription)"
      )
    }

    guard state.layoutVersion == Self.layoutVersion else {
      throw WidgetPackageError.installConflict("unsupported package pin layout")
    }
    guard Set(state.packages).count == state.packages.count else {
      throw WidgetPackageError.installConflict("package pins contain duplicate names")
    }
    for name in state.packages {
      guard WidgetPackageManifestParser.isPackageName(name) else {
        throw WidgetPackageError.installConflict(
          "package pins contain invalid name '\(name)'"
        )
      }
    }

    return Set(state.packages)
  }

  func write(_ pins: Set<String>, to packagesDirectory: URL) throws {
    let url = packagesDirectory.appending(path: "pins.json")
    try fileManager.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )

    let state = WidgetPackagePins(
      layoutVersion: Self.layoutVersion,
      packages: pins.sorted()
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    var data = try encoder.encode(state)
    data.append(0x0A)
    try data.write(to: url, options: .atomic)
  }
}
