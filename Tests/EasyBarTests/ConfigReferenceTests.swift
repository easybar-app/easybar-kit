import EasyBarConfigSchema
import Foundation
import XCTest

final class ConfigReferenceTests: ConfigLoaderTestCase {
  func testGeneratedReferenceContainsEveryDocumentedSchemaKey() throws {
    let referenceURL = repoRootURL()
      .appendingPathComponent("docs/content/configuration/reference.md")
    let reference = try String(contentsOf: referenceURL, encoding: .utf8)

    XCTAssertEqual(referenceKeys(in: reference), documentedSchemaKeys())
  }

  func testGeneratedReferenceDistinguishesDefaultsFromExamples() throws {
    let referenceURL = repoRootURL()
      .appendingPathComponent("docs/content/configuration/reference.md")
    let reference = try String(contentsOf: referenceURL, encoding: .utf8)

    XCTAssertEqual(
      referenceRow(in: reference, section: "app", key: "show_menu_bar_icon"),
      ["`true`", "—"]
    )
    XCTAssertEqual(
      referenceRow(in: reference, section: "builtins.battery", key: "group"),
      ["Not set", "`\"system\"`"]
    )
    XCTAssertEqual(
      referenceRow(in: reference, section: "builtins.privacy_spacer", key: "width"),
      ["`12`", "—"]
    )
    XCTAssertEqual(
      referenceRow(in: reference, section: "app", key: "lua_socket_path"),
      ["Not set", "`\"~/.local/state/easybar/runtime/lua-runtime.sock\"`"]
    )
    XCTAssertEqual(
      referenceRow(in: reference, section: "builtins.calendar.anchor", key: "spacing"),
      ["Not set", "`2`"]
    )
    XCTAssertEqual(
      referenceRow(
        in: reference,
        section: "builtins.calendar.month.popup.calendar",
        key: "first_weekday"
      ),
      ["Not set", "`2`"]
    )
  }

  func testGeneratedReferenceNamesCompleteSchemaSource() throws {
    let referenceURL = repoRootURL()
      .appendingPathComponent("docs/content/configuration/reference.md")
    let reference = try String(contentsOf: referenceURL, encoding: .utf8)

    let provenance =
      "Generated from the `EasyBarConfigSchema` module: "
      + "`ConfigSchema.swift` and the `ConfigSchema*Lines.swift` files."

    XCTAssertTrue(reference.contains(provenance))
    XCTAssertFalse(
      reference.contains(
        "Generated from `Sources/EasyBarConfigSchema/ConfigSchema.swift`."
      )
    )
  }

  private func documentedSchemaKeys() -> Set<String> {
    var keys: Set<String> = []
    var currentSection: String?
    var currentSectionIsDocumented = false

    for line in ConfigSchemaRegistry.lines {
      switch line {
      case .section(let name, _, _, let documented):
        currentSection = name
        currentSectionIsDocumented = documented

      case .entry(let key, _, _, _, _, let documented):
        guard let currentSection, currentSectionIsDocumented, documented else { continue }
        keys.insert("\(currentSection).\(key)")

      case .optionalEntry(let key, _, _):
        guard let currentSection, currentSectionIsDocumented else { continue }
        keys.insert("\(currentSection).\(key)")

      case .blank, .comment:
        continue
      }
    }

    return keys
  }

  private func referenceRow(
    in reference: String,
    section targetSection: String,
    key targetKey: String
  ) -> [String]? {
    var currentSection: String?

    for line in reference.split(separator: "\n", omittingEmptySubsequences: false) {
      let value = String(line)

      if value.hasPrefix("## `"), value.hasSuffix("`") {
        currentSection = String(value.dropFirst(4).dropLast())
        continue
      }

      guard currentSection == targetSection, value.hasPrefix("| `\(targetKey)`") else {
        continue
      }

      let columns = value.split(separator: "|", omittingEmptySubsequences: true)
        .map { String($0).trimmingCharacters(in: .whitespaces) }
      guard columns.count >= 4 else { return nil }
      return [columns[1], columns[2]]
    }

    return nil
  }

  private func referenceKeys(in reference: String) -> Set<String> {
    var keys: Set<String> = []
    var currentSection: String?

    for line in reference.split(separator: "\n", omittingEmptySubsequences: false) {
      let value = String(line)

      if value.hasPrefix("## `"), value.hasSuffix("`") {
        currentSection = String(value.dropFirst(4).dropLast())
        continue
      }

      guard value.hasPrefix("| `"), let currentSection else { continue }
      let columns = value.split(separator: "|", omittingEmptySubsequences: true)
      guard let firstColumn = columns.first else { continue }
      let rawKey = String(firstColumn).trimmingCharacters(in: .whitespaces)
      guard
        rawKey.hasPrefix("`"), rawKey.hasSuffix("`")
      else {
        continue
      }

      keys.insert("\(currentSection).\(rawKey.dropFirst().dropLast())")
    }

    return keys
  }
}
