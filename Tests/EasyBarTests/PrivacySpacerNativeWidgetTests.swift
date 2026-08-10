import XCTest

@testable import EasyBarKit

@MainActor
final class PrivacySpacerNativeWidgetTests: XCTestCase {
  func testSpacerPublishesConfiguredInvisibleWidthAndClearsOnStop() throws {
    let store = WidgetStore()
    var config = Config.SpacerBuiltinConfig.privacyDefault
    config.width = 28

    let widget = SpacerNativeWidget(
      rootID: "builtin_privacy_spacer",
      config: config,
      widgetStore: store
    )

    widget.start()

    let node = try XCTUnwrap(
      store.topLevelNodes(for: .right).first { $0.id == "builtin_privacy_spacer" }
    )
    XCTAssertEqual(node.width, 28)
    XCTAssertEqual(node.order, 1_000)
    XCTAssertEqual(node.text, "")
    XCTAssertEqual(node.backgroundColor, "#00000000")
    XCTAssertEqual(node.receivesMouseHover, false)
    XCTAssertEqual(widget.appEventSubscriptions, [])

    widget.stop()

    XCTAssertFalse(
      store.topLevelNodes(for: .right).contains { $0.id == "builtin_privacy_spacer" }
    )
  }

  func testMultipleNamedSpacersRenderIndependently() throws {
    let store = WidgetStore()

    var firstConfig = Config.SpacerBuiltinConfig.namedDefault
    firstConfig.order = 10
    firstConfig.width = 6

    var secondConfig = Config.SpacerBuiltinConfig.namedDefault
    secondConfig.order = 20
    secondConfig.width = 14

    let first = SpacerNativeWidget(
      rootID: "builtin_spacer:before_clock",
      config: firstConfig,
      widgetStore: store
    )
    let second = SpacerNativeWidget(
      rootID: "builtin_spacer:after_inbox",
      config: secondConfig,
      widgetStore: store
    )

    first.start()
    second.start()

    let nodes = store.topLevelNodes(for: .right)
    XCTAssertEqual(nodes.map(\.id), ["builtin_spacer:before_clock", "builtin_spacer:after_inbox"])
    XCTAssertEqual(nodes.map(\.width), [6, 14])

    first.stop()
    XCTAssertEqual(
      store.topLevelNodes(for: .right).map(\.id),
      ["builtin_spacer:after_inbox"]
    )
  }
}
