import Foundation
import SwiftTOMLEdit

/// Defines the supported widget package manifest parser values.
enum WidgetPackageManifestParser {
  private static let supportedTopLevelKeys: Set<String> = [
    "manifest_version",
    "name",
    "version",
    "minimum_easybar_kit_version",
    "kind",
    "description",
    "license",
    "readme",
    "categories",
    "entrypoint",
    "repository",
    "dependencies",
    "exports",
    "requirements",
    "settings",
  ]

  /// Parses the requested value.
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

    guard table["manifest_version"]?.int == 2 else {
      throw WidgetPackageError.invalidManifest("manifest_version must be 2")
    }
    let unsupportedKeys = Set(table.keys).subtracting(supportedTopLevelKeys).sorted()
    guard unsupportedKeys.isEmpty else {
      throw WidgetPackageError.invalidManifest(
        "unsupported manifest fields: \(unsupportedKeys.joined(separator: ", "))"
      )
    }
    let name = try requiredString("name", in: table)
    guard isPackageName(name) else {
      throw WidgetPackageError.invalidManifest("invalid package name '\(name)'")
    }
    let versionText = try requiredString("version", in: table)
    guard let version = SemanticVersion(versionText) else {
      throw WidgetPackageError.invalidManifest("invalid version '\(versionText)'")
    }
    let minimumEasyBarKitVersionText = try requiredString(
      "minimum_easybar_kit_version",
      in: table
    )
    guard let minimumEasyBarKitVersion = SemanticVersion(minimumEasyBarKitVersionText) else {
      throw WidgetPackageError.invalidManifest(
        "invalid minimum_easybar_kit_version '\(minimumEasyBarKitVersionText)'"
      )
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
      minimumEasyBarKitVersion: minimumEasyBarKitVersion,
      kind: kind,
      entrypoint: entrypoint,
      dependencies: dependencies,
      exports: exports
    )
  }

  /// Returns whether a package name consists entirely of permitted lowercase components.
  static func isPackageName(_ value: String) -> Bool {
    matchesEntireString(value, pattern: "^[a-z0-9]+(?:-[a-z0-9]+)*$")
  }

  /// Returns whether an exported Lua module name consists entirely of valid identifiers.
  static func isModuleName(_ value: String) -> Bool {
    matchesEntireString(
      value,
      pattern: "^[A-Za-z_][A-Za-z0-9_-]*(?:\\.[A-Za-z_][A-Za-z0-9_-]*)*$"
    )
  }

  /// Prevents regex end anchors from accepting an unconsumed trailing newline.
  private static func matchesEntireString(_ value: String, pattern: String) -> Bool {
    guard let match = value.range(of: pattern, options: .regularExpression) else {
      return false
    }
    return match.lowerBound == value.startIndex && match.upperBound == value.endIndex
  }

  /// Returns the required string.
  private static func requiredString(_ key: String, in table: TOMLTable) throws -> String {
    guard let value = table[key]?.string, !value.isEmpty else {
      throw WidgetPackageError.invalidManifest("\(key) must be a non-empty string")
    }
    return value
  }

  /// Returns the string table.
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

  /// Validates package file.
  private static func validatePackageFile(
    _ relativePath: String,
    label: String,
    directory: URL
  ) throws {
    let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
    guard !components.isEmpty,
      !relativePath.hasPrefix("/"),
      components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
    else {
      throw WidgetPackageError.invalidManifest("unsafe or missing \(label): \(relativePath)")
    }

    var current = directory
    for (index, component) in components.enumerated() {
      current.append(path: String(component))
      let values = try? current.resourceValues(forKeys: [
        .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey,
      ])
      let isLastComponent = index == components.count - 1
      let isExpectedType =
        isLastComponent
        ? values?.isRegularFile == true
        : values?.isDirectory == true

      guard isExpectedType, values?.isSymbolicLink != true else {
        throw WidgetPackageError.invalidManifest("unsafe or missing \(label): \(relativePath)")
      }
    }
  }
}
