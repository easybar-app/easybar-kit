import Foundation
import SwiftTOMLEdit

enum WidgetPackageManifestParser {
  static func parse(directory: URL) throws -> WidgetPackageManifest {
    let manifestURL = directory.appending(path: "package.toml")
    let source: String
    do {
      source = try String(contentsOf: manifestURL, encoding: .utf8)
    } catch {
      throw WidgetPackageError.invalidManifest("could not read \(manifestURL.path)")
    }

    let table: TOMLTable
    do {
      table = try TOMLTable(string: source)
    } catch {
      throw WidgetPackageError.invalidManifest(error.localizedDescription)
    }

    guard table["manifest_version"]?.int == 1 else {
      throw WidgetPackageError.invalidManifest("manifest_version must be 1")
    }
    let name = try requiredString("name", in: table)
    guard isPackageName(name) else {
      throw WidgetPackageError.invalidManifest("invalid package name '\(name)'")
    }
    let versionText = try requiredString("version", in: table)
    guard let version = SemanticVersion(versionText) else {
      throw WidgetPackageError.invalidManifest("invalid version '\(versionText)'")
    }
    let kindText = try requiredString("kind", in: table)
    guard let kind = WidgetPackageKind(rawValue: kindText) else {
      throw WidgetPackageError.invalidManifest("kind must be widget or library")
    }

    let entrypoint = table["entrypoint"]?.string
    if kind == .widget {
      guard let entrypoint else {
        throw WidgetPackageError.invalidManifest("widget packages require an entrypoint")
      }
      try validatePackageFile(entrypoint, label: "entrypoint", directory: directory)
      guard entrypoint.lowercased().hasSuffix(".lua") else {
        throw WidgetPackageError.invalidManifest("entrypoint must be a Lua file")
      }
    } else if entrypoint != nil {
      throw WidgetPackageError.invalidManifest("library packages cannot declare an entrypoint")
    }

    let dependencies = try stringTable("dependencies", in: table).mapValues { value in
      guard let constraint = VersionConstraint(value) else {
        throw WidgetPackageError.invalidManifest("invalid dependency constraint '\(value)'")
      }
      return constraint
    }
    for dependency in dependencies.keys where !isPackageName(dependency) || dependency == name {
      throw WidgetPackageError.invalidManifest("invalid dependency '\(dependency)'")
    }

    let exports = try stringTable("exports", in: table)
    for (module, relativePath) in exports {
      guard isModuleName(module) else {
        throw WidgetPackageError.invalidManifest("invalid exported module '\(module)'")
      }
      try validatePackageFile(relativePath, label: "export \(module)", directory: directory)
      guard relativePath.lowercased().hasSuffix(".lua") else {
        throw WidgetPackageError.invalidManifest("export \(module) must be a Lua file")
      }
    }

    return WidgetPackageManifest(
      name: name,
      version: version,
      kind: kind,
      entrypoint: entrypoint,
      dependencies: dependencies,
      exports: exports
    )
  }

  static func isPackageName(_ value: String) -> Bool {
    value.range(of: "^[a-z0-9]+(?:-[a-z0-9]+)*$", options: .regularExpression) != nil
  }

  private static func isModuleName(_ value: String) -> Bool {
    value.range(
      of: "^[A-Za-z_][A-Za-z0-9_-]*(?:\\.[A-Za-z_][A-Za-z0-9_-]*)*$",
      options: .regularExpression
    ) != nil
  }

  private static func requiredString(_ key: String, in table: TOMLTable) throws -> String {
    guard let value = table[key]?.string, !value.isEmpty else {
      throw WidgetPackageError.invalidManifest("\(key) must be a non-empty string")
    }
    return value
  }

  private static func stringTable(_ key: String, in table: TOMLTable) throws -> [String: String] {
    guard let value = table[key] else { return [:] }
    guard let nested = value.table else {
      throw WidgetPackageError.invalidManifest("\(key) must be a table")
    }
    var output: [String: String] = [:]
    for (name, item) in nested {
      guard let string = item.string, !string.isEmpty else {
        throw WidgetPackageError.invalidManifest("\(key).\(name) must be a non-empty string")
      }
      output[name] = string
    }
    return output
  }

  private static func validatePackageFile(
    _ relativePath: String,
    label: String,
    directory: URL
  ) throws {
    guard !relativePath.isEmpty,
      !relativePath.hasPrefix("/"),
      !relativePath.split(separator: "/", omittingEmptySubsequences: false).contains(".."),
      FileManager.default.fileExists(atPath: directory.appending(path: relativePath).path)
    else {
      throw WidgetPackageError.invalidManifest("unsafe or missing \(label): \(relativePath)")
    }
  }
}
