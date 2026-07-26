import Foundation
import SwiftTOMLEdit

/// Native front-app widget backed by `AeroSpaceService` state.
@MainActor
final class FrontAppNativeWidget: NativeWidget {

  let rootID = "builtin_front_app"
  let widgetStore: WidgetStore

  private var config: Config.FrontAppBuiltinConfig
  private let configSnapshotStore: ConfigSnapshotStore
  private let configPersistence: ConfigPersistence
  private let eventObserver: EasyBarEventObserver
  private let aeroSpaceService: AeroSpaceService

  /// Creates the native front-app widget from an immutable config section.
  init(
    config: Config.FrontAppBuiltinConfig,
    widgetStore: WidgetStore,
    configSnapshotStore: ConfigSnapshotStore,
    configPersistence: ConfigPersistence,
    eventHub: EventHub,
    aeroSpaceService: AeroSpaceService
  ) {
    self.config = config
    self.widgetStore = widgetStore
    self.configSnapshotStore = configSnapshotStore
    self.configPersistence = configPersistence
    self.eventObserver = EasyBarEventObserver(eventHub: eventHub)
    self.aeroSpaceService = aeroSpaceService
  }

  /// Starts the widget and registers AeroSpace interest.
  func start() {
    eventObserver.start(
      eventNames: [WidgetEvent.contextMenuClicked.rawValue],
      widgetTargetIDs: [rootID]
    ) { [weak self] payload in
      guard
        let self,
        payload.widgetEvent == .contextMenuClicked,
        payload.widgetID == self.rootID,
        let actionID = payload.actionID
      else { return }

      self.handleContextMenuAction(actionID)
    }

    aeroSpaceService.registerConsumer(rootID) { [weak self] in
      self?.publish()
    }

    publish()
  }

  /// Stops the widget and removes observers.
  func stop() {
    eventObserver.stop()
    aeroSpaceService.unregisterConsumer(rootID)
    clearNodes()
  }

  /// Publishes the currently focused app.
  private func publish() {
    let placement = config.placement
    let style = config.style
    let focused = currentFocusedApp()
    var nodes = makeNodes(
      config: config,
      placement: placement,
      style: style,
      focused: focused
    )

    if let rootIndex = nodes.firstIndex(where: { $0.id == rootID }) {
      nodes[rootIndex].contextMenu = FrontAppContextMenu.make(
        config: config,
        canHideFocusedApp: aeroSpaceService.canHideFocusedApp,
        canRevealFocusedApp: aeroSpaceService.canRevealFocusedApp
      )
    }

    applyNodes(nodes)
  }

  /// Handles one front-app-specific native context-menu action.
  private func handleContextMenuAction(_ actionID: String) {
    guard let action = FrontAppContextMenuAction(id: actionID) else { return }

    switch action {
    case .hideApplication:
      aeroSpaceService.hideFocusedApp()

    case .toggleShowIcon:
      guard !config.showIcon || config.showName else { return }
      var updated = config
      updated.showIcon.toggle()
      persist(
        updated,
        edit: TOMLEdit(
          path: ["builtins", "front_app", "content", "show_icon"],
          value: .bool(updated.showIcon)
        )
      )

    case .toggleShowName:
      guard !config.showName || config.showIcon else { return }
      var updated = config
      updated.showName.toggle()
      persist(
        updated,
        edit: TOMLEdit(
          path: ["builtins", "front_app", "content", "show_name"],
          value: .bool(updated.showName)
        )
      )

    case .revealInFinder:
      aeroSpaceService.revealFocusedAppInFinder()
    }
  }

  private func persist(_ updated: Config.FrontAppBuiltinConfig, edit: TOMLEdit) {
    NativeWidgetConfigUpdate.persist(edits: [edit], using: configPersistence) {
      config = updated
      configSnapshotStore.applyFrontAppOverride(updated)
      publish()
    }
  }

  /// Returns the focused app already resolved by `AeroSpaceService`.
  private func currentFocusedApp() -> (name: String, bundlePath: String?) {
    guard let app = aeroSpaceService.focusedApp else {
      return ("", nil)
    }

    return (app.name, app.bundlePath)
  }

  /// Builds the widget node tree.
  private func makeNodes(
    config: Config.FrontAppBuiltinConfig,
    placement: Config.BuiltinWidgetPlacement,
    style: Config.BuiltinWidgetStyle,
    focused: (name: String, bundlePath: String?)
  ) -> [WidgetNodeState] {
    var nodes = [
      BuiltinNativeNodeFactory.makeRowContainerNode(
        rootID: rootID,
        placement: placement,
        style: style
      )
    ]

    appendIconNode(
      to: &nodes,
      config: config,
      placement: placement,
      style: style,
      focused: focused
    )

    appendLabelNode(
      to: &nodes,
      config: config,
      placement: placement,
      style: style,
      focused: focused
    )

    return nodes
  }

  /// Appends the icon node when enabled.
  private func appendIconNode(
    to nodes: inout [WidgetNodeState],
    config: Config.FrontAppBuiltinConfig,
    placement: Config.BuiltinWidgetPlacement,
    style: Config.BuiltinWidgetStyle,
    focused: (name: String, bundlePath: String?)
  ) {
    guard config.showIcon else { return }

    nodes.append(
      BuiltinNativeNodeFactory.makeChildItemNode(
        rootID: rootID,
        parentID: rootID,
        childID: "\(rootID)_icon",
        position: placement.position,
        order: 0,
        icon: focused.bundlePath == nil ? style.icon : "",
        text: "",
        color: style.textColorHex,
        imagePath: focused.bundlePath,
        imageSize: config.iconSize,
        imageCornerRadius: config.iconCornerRadius
      )
    )
  }

  /// Appends the label node when enabled.
  private func appendLabelNode(
    to nodes: inout [WidgetNodeState],
    config: Config.FrontAppBuiltinConfig,
    placement: Config.BuiltinWidgetPlacement,
    style: Config.BuiltinWidgetStyle,
    focused: (name: String, bundlePath: String?)
  ) {
    guard config.showName else { return }

    nodes.append(
      BuiltinNativeNodeFactory.makeChildItemNode(
        rootID: rootID,
        parentID: rootID,
        childID: "\(rootID)_label",
        position: placement.position,
        order: 1,
        text: focused.name.isEmpty ? config.fallbackText : focused.name,
        color: style.textColorHex
      )
    )
  }
}
