import AppKit
import CoreAudio
import EasyBarShared
import Foundation
import SwiftTOMLEdit

/// Native volume widget with optional inline expansion.
@MainActor
final class VolumeSliderNativeWidget: NativeWidget {

  let rootID = "builtin_volume"
  let widgetStore: WidgetStore

  var appEventSubscriptions: Set<String> {
    [
      AppEvent.volumeChange.rawValue,
      AppEvent.muteChange.rawValue,
      AppEvent.systemWoke.rawValue,
    ]
  }

  var config: Config.VolumeBuiltinConfig
  let configSnapshotStore: ConfigSnapshotStore
  let configPersistence: ConfigPersistence
  let eventObserver: EasyBarEventObserver
  let logger: ProcessLogger
  var isHovered = false
  var isAdjustingSlider = false
  var autoHideTask: Task<Void, Never>?
  var autoHideTaskID: UInt64?
  var nextAutoHideTaskID: UInt64 = 1

  struct SystemVolumeState {
    let clampedSystem: Double
    let roundedValue: Double
    let step: Double
    let isMuted: Bool
    let capabilities: AudioDeviceCapabilities
  }

  struct Snapshot {
    let config: Config.VolumeBuiltinConfig
    let placement: Config.BuiltinWidgetPlacement
    var style: Config.BuiltinWidgetStyle
    let text: String
    let value: Double
    let step: Double
    let isHovered: Bool
    let isMuted: Bool
    let capabilities: AudioDeviceCapabilities
  }

  /// Creates the native volume widget from an immutable config section.
  init(
    config: Config.VolumeBuiltinConfig,
    widgetStore: WidgetStore,
    configSnapshotStore: ConfigSnapshotStore,
    configPersistence: ConfigPersistence,
    eventHub: EventHub,
    logger: ProcessLogger
  ) {
    self.config = config
    self.widgetStore = widgetStore
    self.configSnapshotStore = configSnapshotStore
    self.configPersistence = configPersistence
    self.eventObserver = EasyBarEventObserver(eventHub: eventHub)
    self.logger = logger
  }

  // MARK: - Lifecycle

  /// Starts the volume widget.
  func start() {
    eventObserver.start(
      eventNames: appEventSubscriptions.union([
        WidgetEvent.mouseEntered.rawValue,
        WidgetEvent.mouseExited.rawValue,
        WidgetEvent.sliderPreview.rawValue,
        WidgetEvent.sliderChanged.rawValue,
        WidgetEvent.contextMenuClicked.rawValue,
      ]),
      widgetTargetIDs: [rootID, "\(rootID)_slider"]
    ) { [weak self] payload in
      guard let self, !self.handleAppEvent(payload) else { return }
      self.handleWidgetEvent(payload)
    }

    publish()
  }

  /// Stops the volume widget.
  func stop() {
    eventObserver.stop()
    cancelAutoHide()
    isHovered = false
    isAdjustingSlider = false

    clearNodes()
  }

  // MARK: - Publish

  /// Publishes the current volume widget state.
  func publish() {
    let snapshot = makeSnapshot()
    var nodes = makeNodes(snapshot: snapshot)
    let contextMenu = VolumeContextMenu.make(
      config: config,
      isMuted: snapshot.isMuted,
      capabilities: snapshot.capabilities
    )
    if let rootIndex = nodes.firstIndex(where: { $0.id == rootID }) {
      nodes[rootIndex].contextMenu = contextMenu
    }
    applyNodes(nodes)
  }

  /// Returns the current render snapshot.
  func makeSnapshot() -> Snapshot {
    let placement = config.placement
    let volumeState = currentSystemVolumeState(config: config)
    let style = config.style.widgetStyle(
      icon: resolvedIcon(
        for: volumeState.clampedSystem,
        muted: volumeState.isMuted,
        config: config
      )
    )

    let text = VolumePresentation.percentageText(
      normalizedVolume: volumeState.clampedSystem,
      config: config,
      isHovered: isHovered,
      canReadVolume: volumeState.capabilities.canReadVolume,
      canSetVolume: volumeState.capabilities.canSetVolume
    )

    return Snapshot(
      config: config,
      placement: placement,
      style: style,
      text: text,
      value: volumeState.roundedValue,
      step: volumeState.step,
      isHovered: isHovered,
      isMuted: volumeState.isMuted,
      capabilities: volumeState.capabilities
    )
  }

  private func makeNodes(snapshot: Snapshot) -> [WidgetNodeState] {
    guard snapshot.capabilities.canSetVolume else {
      return [
        BuiltinNativeNodeFactory.makeItemNode(
          rootID: rootID,
          placement: snapshot.placement,
          style: snapshot.style,
          text: snapshot.text
        )
      ]
    }

    guard !snapshot.config.expandToSliderOnHover else {
      return makeExpandableNodes(snapshot: snapshot)
    }

    return [
      BuiltinNativeNodeFactory.makeProgressSliderNode(
        rootID: rootID,
        placement: snapshot.placement,
        style: snapshot.style,
        text: snapshot.text,
        value: snapshot.value,
        min: snapshot.config.minValue,
        max: snapshot.config.maxValue,
        step: snapshot.step,
        width: snapshot.config.sliderWidth
      )
    ]
  }

  private func makeExpandableNodes(snapshot: Snapshot) -> [WidgetNodeState] {
    var nodes: [WidgetNodeState] = [
      BuiltinNativeNodeFactory.makeRowContainerNode(
        rootID: rootID,
        placement: snapshot.placement,
        style: snapshot.style
      )
    ]

    if !snapshot.style.icon.isEmpty {
      nodes.append(
        BuiltinNativeNodeFactory.makeChildItemNode(
          rootID: rootID,
          parentID: rootID,
          childID: "\(rootID)_icon",
          position: snapshot.placement.position,
          order: 0,
          icon: snapshot.style.icon,
          color: snapshot.style.textColorHex
        )
      )
    }

    nodes.append(
      BuiltinNativeNodeFactory.makeChildItemNode(
        rootID: rootID,
        parentID: rootID,
        childID: "\(rootID)_label",
        position: snapshot.placement.position,
        order: 1,
        text: snapshot.text,
        color: snapshot.style.textColorHex,
        visible: snapshot.isHovered && !snapshot.text.isEmpty
      )
    )

    nodes.append(
      BuiltinNativeNodeFactory.makeChildProgressSliderNode(
        rootID: rootID,
        parentID: rootID,
        childID: "\(rootID)_slider",
        position: snapshot.placement.position,
        order: 2,
        value: snapshot.value,
        min: snapshot.config.minValue,
        max: snapshot.config.maxValue,
        step: snapshot.step,
        color: snapshot.style.textColorHex,
        visible: snapshot.isHovered,
        width: snapshot.config.sliderWidth
      )
    )

    return nodes
  }

  // MARK: - Context Menu

  /// Handles one volume-specific native context-menu action.
  func handleContextMenuAction(_ actionID: String) {
    guard let action = VolumeContextMenuAction(id: actionID) else { return }

    switch action {
    case .toggleMute:
      guard currentAudioDeviceCapabilities().canMute else {
        logger.warn("volume mute action unavailable for current output device")
        return
      }
      _ = setMutedState(!readMutedState())
      publish()

    case .toggleShowPercentage:
      var updated = config
      updated.showPercentage.toggle()
      persist(
        updated,
        edit: TOMLEdit(
          path: ["builtins", "volume", "content", "show_percentage"],
          value: .bool(updated.showPercentage)
        )
      )

    case .toggleExpandOnHover:
      guard currentAudioDeviceCapabilities().canSetVolume else {
        logger.warn("volume slider mode unavailable for current output device")
        return
      }
      var updated = config
      updated.expandToSliderOnHover.toggle()
      persist(
        updated,
        edit: TOMLEdit(
          path: ["builtins", "volume", "slider", "expand_to_slider_on_hover"],
          value: .bool(updated.expandToSliderOnHover)
        )
      )

    case .openSoundSettings:
      guard let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")
      else {
        logger.warn("failed to build Sound Settings URL")
        return
      }
      guard NSWorkspace.shared.open(url) else {
        logger.warn("failed to open Sound Settings")
        return
      }
      logger.debug("opened Sound Settings")
    }
  }

  private func persist(_ updated: Config.VolumeBuiltinConfig, edit: TOMLEdit) {
    NativeWidgetConfigUpdate.persist(edits: [edit], using: configPersistence) {
      config = updated
      configSnapshotStore.applyVolumeOverride(updated)
      publish()
    }
  }
}
