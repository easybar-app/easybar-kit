import Foundation

struct WidgetPackageRegistryLoader {
  static let defaultSource =
    "https://raw.githubusercontent.com/easybar-app/widget-registry/main/index.json"
  private static let maximumBytes = 5 * 1_024 * 1_024

  func load(source: String?) async throws -> PackageRegistryIndex {
    let selectedSource = source ?? Self.defaultSource
    let url = try sourceURL(selectedSource)
    let data = try await loadData(from: url)
    let registry: PackageRegistryIndex
    do {
      registry = try JSONDecoder().decode(PackageRegistryIndex.self, from: data)
    } catch {
      throw WidgetPackageError.invalidRegistry(error.localizedDescription)
    }
    guard registry.registryVersion == 1 else {
      throw WidgetPackageError.invalidRegistry("registry_version must be 1")
    }
    guard Set(registry.packages.map(\.name)).count == registry.packages.count else {
      throw WidgetPackageError.invalidRegistry("registry contains duplicate package names")
    }
    return registry
  }

  private func sourceURL(_ source: String) throws -> URL {
    if let url = URL(string: source),
      let scheme = url.scheme?.lowercased(),
      ["https", "http", "file"].contains(scheme)
    {
      return url
    }

    let path = NSString(string: source).expandingTildeInPath
    guard FileManager.default.fileExists(atPath: path) else {
      throw WidgetPackageError.invalidRegistry("source does not exist: \(source)")
    }
    return URL(fileURLWithPath: path)
  }

  private func loadData(from url: URL) async throws -> Data {
    let data: Data
    if url.isFileURL {
      data = try Data(contentsOf: url)
    } else {
      let (downloaded, response) = try await URLSession.shared.data(from: url)
      if let response = response as? HTTPURLResponse,
        !(200...299).contains(response.statusCode)
      {
        throw WidgetPackageError.invalidRegistry(
          "\(url.absoluteString) returned HTTP \(response.statusCode)"
        )
      }
      data = downloaded
    }
    guard data.count <= Self.maximumBytes else {
      throw WidgetPackageError.invalidRegistry(
        "registry exceeds the \(Self.maximumBytes)-byte limit"
      )
    }
    return data
  }
}
