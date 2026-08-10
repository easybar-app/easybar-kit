import EasyBarCalendarConfig
import XCTest

@testable import EasyBarKit

final class CalendarContextMenuTests: XCTestCase {
  func testMenuReflectsEffectiveCalendarOptions() throws {
    var config = CalendarBuiltinConfig.default
    config.popupMode = .upcoming
    config.anchor.layout = .column
    config.anchor.fields = [.time]
    config.appointments.showLocation = false
    config.month.popup.todayMarkerVariant = .openLoop
    config.month.popup.todayMarkerSize = 24

    let menu = CalendarContextMenu.make(config: config)
    let validated = try XCTUnwrap(WidgetContextMenuItem.validated(menu))
    let popupItems = try submenu(named: "Popup", in: validated)
    let layoutItems = try submenu(named: "Anchor Layout", in: validated)
    let anchorItems = try submenu(named: "Anchor Fields", in: validated)
    let todayItems = try submenu(named: "Today", in: validated)
    let markerStyleItems = try submenu(named: "Marker Style", in: todayItems)
    let markerSizeItems = try submenu(named: "Marker Size", in: todayItems)
    let appointmentItems = try submenu(named: "Appointment Details", in: validated)

    XCTAssertEqual(
      popupItems.first(where: { $0.id == "calendar.popup.upcoming" })?.checked,
      true
    )
    XCTAssertEqual(
      layoutItems.first(where: { $0.id == "calendar.layout.column" })?.checked,
      true
    )
    XCTAssertEqual(
      anchorItems.first(where: { $0.id == "calendar.anchor_field.time" })?.enabled,
      false
    )
    XCTAssertEqual(
      appointmentItems.first(where: { $0.id == "calendar.appointment.location" })?.checked,
      false
    )
    XCTAssertEqual(
      markerStyleItems.first(where: { $0.id == "calendar.today_marker.variant.open_loop" })?.checked,
      true
    )
    XCTAssertEqual(
      markerSizeItems.first(where: { $0.id == "calendar.today_marker.size.24" })?.checked,
      true
    )
  }

  func testMenuPreservesCustomTodayMarkerSize() throws {
    var config = CalendarBuiltinConfig.default
    config.month.popup.todayMarkerSize = 22.5

    let menu = try XCTUnwrap(
      WidgetContextMenuItem.validated(CalendarContextMenu.make(config: config))
    )
    let todayItems = try submenu(named: "Today", in: menu)
    let markerSizeItems = try submenu(named: "Marker Size", in: todayItems)

    XCTAssertEqual(markerSizeItems.first?.id, CalendarContextMenuAction.customTodayMarkerSizeID)
    XCTAssertEqual(markerSizeItems.first?.title, "Custom: 22.5 pt")
    XCTAssertEqual(markerSizeItems.first?.enabled, false)
    XCTAssertEqual(markerSizeItems.first?.checked, true)
  }

  func testActionIdentifiersRejectUnknownOptions() {
    XCTAssertEqual(
      CalendarContextMenuAction(id: "calendar.popup.month"),
      .setPopupMode(.month)
    )
    XCTAssertEqual(
      CalendarContextMenuAction(id: "calendar.layout.row"),
      .setAnchorLayout(.row)
    )
    XCTAssertEqual(
      CalendarContextMenuAction(id: "calendar.anchor_field.date"),
      .toggleAnchorField(.date)
    )
    XCTAssertEqual(
      CalendarContextMenuAction(id: "calendar.today_marker.variant.soft_wobble"),
      .setTodayMarkerVariant(.softWobble)
    )
    XCTAssertEqual(
      CalendarContextMenuAction(id: "calendar.today_marker.size.22"),
      .setTodayMarkerSize(22)
    )
    XCTAssertEqual(
      CalendarContextMenuAction(id: "calendar.appointment.location"),
      .toggleAppointmentOption("location")
    )
    XCTAssertEqual(CalendarContextMenuAction(id: "calendar.refresh"), .refresh)
    XCTAssertNil(CalendarContextMenuAction(id: "calendar.save_to_config"))
    XCTAssertNil(CalendarContextMenuAction(id: "calendar.appointment.unknown"))
    XCTAssertNil(CalendarContextMenuAction(id: "calendar.today_marker.variant.unknown"))
    XCTAssertNil(CalendarContextMenuAction(id: "calendar.today_marker.size.23"))
    XCTAssertNil(CalendarContextMenuAction(id: "calendar.unknown"))
  }

  @MainActor
  func testSnapshotStoreAppliesOnlyCalendarSessionOverride() {
    let original = Config.makeUnloadedConfig().snapshot()
    let store = ConfigSnapshotStore(snapshot: original)
    var calendar = original.builtins.calendar
    calendar.popupMode = .none

    store.applyCalendarSessionOverride(calendar)

    XCTAssertEqual(store.snapshot.builtins.calendar.popupMode, .none)
    XCTAssertEqual(store.snapshot.builtins.wifi.mode, original.builtins.wifi.mode)
    XCTAssertEqual(store.snapshot.theme.name, original.theme.name)
  }

  private func submenu(
    named title: String,
    in items: [WidgetContextMenuItem]
  ) throws -> [WidgetContextMenuItem] {
    try XCTUnwrap(items.first(where: { $0.title == title })?.submenu)
  }
}
