import EasyBarCalendarConfig
import Foundation
import SwiftTOMLEdit
import XCTest

@testable import EasyBarKit

final class CalendarAnchorConfigurationTests: XCTestCase {
  func testParsesOrderedFieldsAndIndependentStyles() throws {
    let table = try TOMLTable(
      string: """
        [anchor]
        layout = "row"
        fields = ["date", "time"]
        spacing = 2
        separator = " / "

        [anchor.time]
        format = "HH:mm:ss"
        font_family = "Menlo"
        font_size = 14
        font_weight = "bold"
        text_color = "#ffffff"

        [anchor.date]
        format = "yyyy-MM-dd"
        font_size = 11
        font_weight = "light"
        text_color = "#aaaaaa"
        """
    )

    let config = try CalendarBuiltinConfig.parse(from: table)

    XCTAssertEqual(config.anchor.layout, .row)
    XCTAssertEqual(config.anchor.fields, [.date, .time])
    XCTAssertEqual(config.anchor.spacing, 2)
    XCTAssertEqual(config.anchor.separator, " / ")
    XCTAssertEqual(config.anchor.time.format, "HH:mm:ss")
    XCTAssertEqual(config.anchor.time.fontFamily, "Menlo")
    XCTAssertEqual(config.anchor.time.fontSize, 14)
    XCTAssertEqual(config.anchor.time.fontWeight, .bold)
    XCTAssertEqual(config.anchor.date.format, "yyyy-MM-dd")
    XCTAssertEqual(config.anchor.date.fontSize, 11)
    XCTAssertEqual(config.anchor.date.fontWeight, .light)
  }

  func testRowRendererUsesFieldOrderSeparatorAndStyles() throws {
    var config = CalendarBuiltinConfig.default
    config.anchor.layout = .row
    config.anchor.fields = [.date, .time]
    config.anchor.separator = ", "
    config.anchor.date.format = "yyyy"
    config.anchor.date.fontFamily = "Menlo"
    config.anchor.date.fontSize = 11
    config.anchor.date.fontWeight = .semibold
    config.anchor.time.format = "HH"

    let nodes = CalendarRenderer(rootID: "calendar").makeNodes(
      snapshot: .init(config: config, now: Date(timeIntervalSince1970: 0))
    )

    XCTAssertEqual(nodes.first(where: { $0.id == "calendar_fields" })?.kind, .row)
    XCTAssertEqual(nodes.first(where: { $0.id == "calendar_field_0_date" })?.text, "1970")
    XCTAssertEqual(nodes.first(where: { $0.id == "calendar_separator_1" })?.text, ", ")
    XCTAssertEqual(nodes.first(where: { $0.id == "calendar_field_0_date" })?.labelFontFamily, "Menlo")
    XCTAssertEqual(nodes.first(where: { $0.id == "calendar_field_0_date" })?.labelFontSize, 11)
    XCTAssertEqual(
      nodes.first(where: { $0.id == "calendar_field_0_date" })?.labelFontWeight,
      "semibold"
    )
  }

  func testColumnRendererReversesFieldsWithoutSeparator() {
    var config = CalendarBuiltinConfig.default
    config.anchor.layout = .column
    config.anchor.fields = [.date, .time]

    let nodes = CalendarRenderer(rootID: "calendar").makeNodes(
      snapshot: .init(config: config, now: Date(timeIntervalSince1970: 0))
    )

    XCTAssertEqual(nodes.first(where: { $0.id == "calendar_fields" })?.kind, .column)
    XCTAssertEqual(nodes.first(where: { $0.id == "calendar_field_0_date" })?.order, 0)
    XCTAssertEqual(nodes.first(where: { $0.id == "calendar_field_1_time" })?.order, 2)
    XCTAssertFalse(nodes.contains(where: { $0.id.contains("separator") }))
  }

  func testOnlyCalendarRootOwnsNativePopup() {
    let nodes = CalendarRenderer(rootID: "builtin_calendar").makeNodes(
      snapshot: .init(
        config: CalendarBuiltinConfig.default,
        now: Date(timeIntervalSince1970: 0)
      )
    )

    XCTAssertEqual(nodes.filter(\.isCalendarRoot).map(\.id), ["builtin_calendar"])
  }
}
