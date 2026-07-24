import EasyBarShared
import XCTest

@testable import EasyBarApp

@MainActor
final class PrivacySpacerNativeWidgetTests: XCTestCase {
  func testPublishesConfiguredInvisibleWidthAndClearsOnStop() throws {
    let store = WidgetStore()
    var config = Config.PrivacySpacerBuiltinConfig.default
    config.enabled = true
    config.width = 28

    let widget = PrivacySpacerNativeWidget(
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
    XCTAssertFalse(node.receivesMouseHover)

    widget.stop()

    XCTAssertFalse(
      store.topLevelNodes(for: .right).contains { $0.id == "builtin_privacy_spacer" }
    )
  }
}
