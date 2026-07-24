import Foundation

/// Native invisible spacer that reserves a fixed amount of bar width.
@MainActor
final class SpacerNativeWidget: NativeWidget {
  let rootID: String
  let widgetStore: WidgetStore

  private let config: Config.SpacerBuiltinConfig

  init(
    rootID: String,
    config: Config.SpacerBuiltinConfig,
    widgetStore: WidgetStore
  ) {
    self.rootID = rootID
    self.config = config
    self.widgetStore = widgetStore
  }

  /// Publishes the invisible spacer node.
  func start() {
    publish()
  }

  /// Removes the spacer node.
  func stop() {
    widgetStore.apply(owner: .native(root: rootID), nodes: [])
  }

  private func publish() {
    let style = Config.BuiltinWidgetStyle(
      icon: "",
      textColorHex: "#00000000",
      backgroundColorHex: "#00000000",
      borderColorHex: "#00000000",
      borderWidth: 0,
      cornerRadius: 0,
      marginX: 0,
      marginY: 0,
      paddingX: 0,
      paddingY: 0,
      spacing: 0,
      opacity: 1
    )

    var node = BuiltinNativeNodeFactory.makeItemNode(
      rootID: rootID,
      placement: config.placement,
      style: style,
      text: ""
    )
    node.width = config.width
    node.height = 1
    node.receivesMouseHover = false
    node.receivesMouseDown = false
    node.receivesMouseUp = false
    node.receivesMouseClick = false
    node.receivesMouseScroll = false
    widgetStore.apply(owner: .native(root: rootID), nodes: [node])
  }
}
