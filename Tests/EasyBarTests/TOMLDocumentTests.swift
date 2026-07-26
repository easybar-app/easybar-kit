import SwiftTOMLEdit
import XCTest

final class TOMLDocumentTests: XCTestCase {
  func testParseProvidesTypedValues() throws {
    let table = try TOMLTable(
      string: """
        title = "EasyBar"
        enabled = true
        count = 3
        ratio = 1.5
        fields = ["time", "date"]

        [nested]
        value = "kept"
        """
    )

    XCTAssertEqual(table["title"]?.string, "EasyBar")
    XCTAssertEqual(table["enabled"]?.bool, true)
    XCTAssertEqual(table["count"]?.int, 3)
    XCTAssertEqual(table["ratio"]?.double, 1.5)
    XCTAssertEqual(table["fields"]?.array?.compactMap(\.string), ["time", "date"])
    XCTAssertEqual(table["nested"]?.table?["value"]?.string, "kept")
  }

  func testEditPreservesCommentsWhitespaceAndUnchangedOrdering() throws {
    let source = """
      # User heading
      [builtins.calendar]
      popup_mode   = "month" # Keep inline explanation

      # Keep this block attached to the next setting
      enabled = true
      """

    let edited = try TOMLDocument.edit(
      source,
      edits: [
        TOMLEdit(
          path: ["builtins", "calendar", "popup_mode"],
          value: .string("upcoming")
        )
      ]
    )

    XCTAssertEqual(
      edited,
      source.replacingOccurrences(of: "\"month\"", with: "\"upcoming\"")
    )
  }

  func testEditAddsMissingNestedTablesAndArray() throws {
    let edited = try TOMLDocument.edit(
      "# Existing comment\n",
      edits: [
        TOMLEdit(
          path: ["builtins", "calendar", "anchor", "fields"],
          value: .stringArray(["date", "time"])
        )
      ]
    )
    let table = try TOMLTable(string: edited)

    XCTAssertTrue(edited.contains("# Existing comment"))
    XCTAssertEqual(
      table["builtins"]?.table?["calendar"]?.table?["anchor"]?.table?["fields"]?.array?
        .compactMap(\.string),
      ["date", "time"]
    )
  }

  func testEditPreservesInlineTablesAndComments() throws {
    let source =
      "builtins = { inbox = { content = { show_when_empty = true, max_items = 10 } } } # Keep me\n"

    let edited = try TOMLDocument.edit(
      source,
      edits: [
        TOMLEdit(
          path: ["builtins", "inbox", "content", "show_when_empty"],
          value: .bool(false)
        )
      ]
    )

    XCTAssertEqual(
      edited,
      source.replacingOccurrences(of: "show_when_empty = true", with: "show_when_empty = false")
    )
  }

  func testParseErrorContainsSourceLocation() {
    XCTAssertThrowsError(try TOMLTable(string: "[broken\nvalue = true")) { error in
      guard let parseError = error as? TOMLParseError else {
        return XCTFail("Unexpected error: \(error)")
      }
      XCTAssertEqual(parseError.line, 1)
      XCTAssertNotNil(parseError.column)
      XCTAssertFalse(parseError.message.isEmpty)
    }
  }
}
