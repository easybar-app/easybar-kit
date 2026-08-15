import Foundation

struct WidgetPackageSearcher {
  private let loader: WidgetPackageRegistryLoader

  init(loader: WidgetPackageRegistryLoader = WidgetPackageRegistryLoader()) {
    self.loader = loader
  }

  func search(
    query: String?,
    registrySource: String?,
    refreshRegistry: Bool = false
  ) async throws -> [PackageRegistryEntry] {
    let registry = try await loader.load(
      source: registrySource,
      refresh: refreshRegistry
    )
    let normalizedQuery = query?.trimmingCharacters(in: .whitespacesAndNewlines)

    return registry.packages
      .filter { package in
        guard let normalizedQuery, !normalizedQuery.isEmpty else { return true }
        return package.name.localizedStandardContains(normalizedQuery)
          || package.description.localizedStandardContains(normalizedQuery)
          || package.kind.rawValue.localizedStandardContains(normalizedQuery)
          || package.categories.contains(where: { $0.localizedStandardContains(normalizedQuery) })
      }
      .sorted { $0.name < $1.name }
  }
}

func searchWidgetPackages(
  options: WidgetPackageSearchOptions,
  context: AppContext
) async throws {
  do {
    context.debug("searching widget registry")
    let packages = try await WidgetPackageSearcher().search(
      query: options.query,
      registrySource: options.registry,
      refreshRegistry: options.refreshRegistry
    )
    CLIOutput.printWidgetPackageSearchResults(packages)
  } catch {
    throw AppError.commandFailed(error.localizedDescription)
  }
}
