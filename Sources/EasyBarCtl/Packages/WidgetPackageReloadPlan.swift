import Foundation

struct WidgetPackageReloadPlan: Codable, Equatable {
  let packages: [String]
  let modules: [String]
  let widgets: [String]

  var isEmpty: Bool {
    packages.isEmpty
  }
}

enum WidgetPackageReloadPlanner {
  static func make(
    changedNames: Set<String>,
    packages: [InstalledWidgetPackage]
  ) throws -> WidgetPackageReloadPlan {
    guard !changedNames.isEmpty else {
      return WidgetPackageReloadPlan(packages: [], modules: [], widgets: [])
    }

    let byName = Dictionary(uniqueKeysWithValues: packages.map { ($0.name, $0) })
    var affected = Set(changedNames.filter { byName[$0] != nil })
    var changed = true

    while changed {
      changed = false
      for package in packages where !affected.contains(package.name) {
        if package.dependencies.keys.contains(where: affected.contains) {
          affected.insert(package.name)
          changed = true
        }
      }
    }

    let order = try dependencyOrder(for: affected, packages: byName)
    var modules: [String] = []
    var widgets: [String] = []

    for name in order {
      guard let package = byName[name] else { continue }
      modules.append(contentsOf: package.exports.keys.sorted())
      if package.kind == .widget {
        widgets.append(name)
      }
    }

    return WidgetPackageReloadPlan(packages: order, modules: modules, widgets: widgets)
  }

  private static func dependencyOrder(
    for affected: Set<String>,
    packages: [String: InstalledWidgetPackage]
  ) throws -> [String] {
    var indegree = Dictionary(uniqueKeysWithValues: affected.map { ($0, 0) })
    var dependents: [String: [String]] = [:]

    for name in affected.sorted() {
      guard let package = packages[name] else { continue }
      for dependency in package.dependencies.keys.sorted() where affected.contains(dependency) {
        indegree[name, default: 0] += 1
        dependents[dependency, default: []].append(name)
      }
    }

    for dependency in dependents.keys {
      dependents[dependency]?.sort()
    }

    var ready = indegree.compactMap { name, degree in degree == 0 ? name : nil }.sorted()
    var order: [String] = []

    while !ready.isEmpty {
      let name = ready.removeFirst()
      order.append(name)

      for dependent in dependents[name] ?? [] {
        guard let degree = indegree[dependent] else { continue }
        let next = degree - 1
        indegree[dependent] = next
        if next == 0 {
          ready.append(dependent)
          ready.sort()
        }
      }
    }

    guard order.count == affected.count else {
      let unresolved = affected.subtracting(order).sorted().joined(separator: ", ")
      throw WidgetPackageError.installConflict(
        "installed widget package dependency graph contains a cycle: \(unresolved)"
      )
    }

    return order
  }
}

struct WidgetPackageReloadPlanStore {
  static let fileName = ".reload-plan.json"

  private let fileManager: FileManager

  init(fileManager: FileManager = .default) {
    self.fileManager = fileManager
  }

  func write(_ plan: WidgetPackageReloadPlan, to packagesDirectory: URL) throws {
    guard !plan.isEmpty else {
      remove(from: packagesDirectory)
      return
    }

    try fileManager.createDirectory(at: packagesDirectory, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    var data = try encoder.encode(plan)
    data.append(0x0A)
    try data.write(to: url(in: packagesDirectory), options: .atomic)
  }

  func remove(from packagesDirectory: URL) {
    try? fileManager.removeItem(at: url(in: packagesDirectory))
  }

  func url(in packagesDirectory: URL) -> URL {
    packagesDirectory.appending(path: Self.fileName, directoryHint: .notDirectory)
  }
}
