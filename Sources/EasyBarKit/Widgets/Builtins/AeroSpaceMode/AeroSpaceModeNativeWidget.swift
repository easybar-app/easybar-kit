import Foundation
import SwiftTOMLEdit

/// Native AeroSpace layout-mode widget backed by `AeroSpaceService` state.
@MainActor
final class AeroSpaceModeNativeWidget: NativeWidget {

  let rootID = "builtin_aerospace_mode"
  let widgetStore: WidgetStore

  private var config: Config.AeroSpaceModeBuiltinConfig
  private let configSnapshotStore: ConfigSnapshotStore
  private let configPersistence: ConfigPersistence
  private let eventObserver: EasyBarEventObserver
  private let aeroSpaceService: AeroSpaceService

  /// Creates the native AeroSpace mode widget from an immutable config section.
  init(
    config: Config.AeroSpaceModeBuiltinConfig,
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

  /// Publishes the currently focused AeroSpace layout mode.
  private func publish() {
    let placement = config.placement
    let mode = aeroSpaceService.focusedLayoutMode

    var node = BuiltinNativeNodeFactory.makeItemNode(
      rootID: rootID,
      placement: placement,
      style: config.style.widgetStyle(icon: resolvedIcon(for: mode, config: config)),
      text: resolvedText(for: mode, config: config)
    )
    node.contextMenu = AeroSpaceModeContextMenu.make(
      config: config,
      currentLayout: mode
    )

    applyNodes([node])
  }

  /// Handles one AeroSpace-mode-specific native context-menu action.
  private func handleContextMenuAction(_ actionID: String) {
    guard let action = AeroSpaceModeContextMenuAction(id: actionID) else { return }

    switch action {
    case .setLayout(let mode):
      aeroSpaceService.setFocusedLayout(mode)

    case .toggleShowIcon:
      guard !config.showIcon || config.showText else { return }
      var updated = config
      updated.showIcon.toggle()
      persist(
        updated,
        edit: TOMLEdit(
          path: ["builtins", "aerospace_mode", "content", "show_icon"],
          value: .bool(updated.showIcon)
        )
      )

    case .toggleShowText:
      guard !config.showText || config.showIcon else { return }
      var updated = config
      updated.showText.toggle()
      persist(
        updated,
        edit: TOMLEdit(
          path: ["builtins", "aerospace_mode", "content", "show_text"],
          value: .bool(updated.showText)
        )
      )

    case .openConfig:
      aeroSpaceService.openConfig()

    case .refresh:
      aeroSpaceService.refresh()
    }
  }

  private func persist(_ updated: Config.AeroSpaceModeBuiltinConfig, edit: TOMLEdit) {
    NativeWidgetConfigUpdate.persist(edits: [edit], using: configPersistence) {
      config = updated
      configSnapshotStore.applyAeroSpaceModeOverride(updated)
      publish()
    }
  }

  /// Returns the configured icon for the current layout mode.
  private func resolvedIcon(
    for mode: AeroSpaceLayoutMode,
    config: Config.AeroSpaceModeBuiltinConfig
  ) -> String {
    guard config.showIcon else { return "" }

    switch mode {
    case .hTiles:
      return config.hTilesIcon
    case .vTiles:
      return config.vTilesIcon
    case .hAccordion:
      return config.hAccordionIcon
    case .vAccordion:
      return config.vAccordionIcon
    case .floating:
      return config.floatingIcon
    case .unknown:
      return config.unknownIcon
    }
  }

  /// Returns the configured label for the current layout mode.
  private func resolvedText(
    for mode: AeroSpaceLayoutMode,
    config: Config.AeroSpaceModeBuiltinConfig
  ) -> String {
    guard config.showText else { return "" }

    switch mode {
    case .hTiles:
      return config.hTilesText
    case .vTiles:
      return config.vTilesText
    case .hAccordion:
      return config.hAccordionText
    case .vAccordion:
      return config.vAccordionText
    case .floating:
      return config.floatingText
    case .unknown:
      return config.unknownText
    }
  }
}
