import AppKit
import EasyBarShared
import Foundation
import SwiftTOMLEdit

/// Native Wi-Fi widget backed by the network agent snapshot store.
@MainActor
final class WiFiNativeWidget: NativeWidget {

  let rootID = "builtin_wifi"
  let widgetStore: WidgetStore

  var appEventSubscriptions: Set<String> {
    [
      AppEvent.networkChange.rawValue
    ]
  }

  private var configuredConfig: Config.WiFiBuiltinConfig
  private let configPersistence: ConfigPersistence
  private let networkAgentConfig: ConfigSnapshot.NetworkAgent
  private let networkAgentClient: NetworkAgentClient
  private let nativeWiFiStore: NativeWiFiStore
  private let eventObserver: EasyBarEventObserver
  private var sessionConfig: Config.WiFiBuiltinConfig
  private var isHovered = false
  private var started = false
  private var startedNetworkAgent = false
  private lazy var renderer = WiFiRenderer(rootID: rootID)

  struct Snapshot {
    let config: Config.WiFiBuiltinConfig
    let network: NetworkAgentSnapshot?
    let content: WiFiPresentation.Content
    let signalLevel: Int
    let visualState: WiFiPresentation.VisualState
    let activeColorHex: String
    let inactiveColorHex: String
    let inlineContentVisible: Bool
    let detailsContentVisible: Bool
  }

  /// Creates the native Wi-Fi widget from immutable config sections.
  init(
    config: Config.WiFiBuiltinConfig,
    networkAgentConfig: ConfigSnapshot.NetworkAgent,
    widgetStore: WidgetStore,
    networkAgentClient: NetworkAgentClient,
    nativeWiFiStore: NativeWiFiStore,
    configPersistence: ConfigPersistence,
    eventHub: EventHub
  ) {
    self.configuredConfig = config
    self.configPersistence = configPersistence
    self.networkAgentConfig = networkAgentConfig
    self.widgetStore = widgetStore
    self.networkAgentClient = networkAgentClient
    self.nativeWiFiStore = nativeWiFiStore
    self.eventObserver = EasyBarEventObserver(eventHub: eventHub)
    self.sessionConfig = config
  }

  // MARK: - Lifecycle

  /// Starts the Wi-Fi widget.
  func start() {
    guard !started else { return }
    started = true

    eventObserver.start(
      eventNames: appEventSubscriptions.union([
        WidgetEvent.mouseEntered.rawValue,
        WidgetEvent.mouseExited.rawValue,
        WidgetEvent.contextMenuClicked.rawValue,
      ]),
      widgetTargetIDs: [rootID]
    ) { [weak self] payload in
      guard let self, !self.handleAppEvent(payload) else { return }
      self.handleWidgetEvent(payload)
    }

    startedNetworkAgent = configuredConfig.enabled && networkAgentConfig.enabled

    guard startedNetworkAgent else {
      publish()
      return
    }

    networkAgentClient.start()
    publish()
  }

  /// Stops the Wi-Fi widget.
  func stop() {
    guard started else { return }
    started = false

    eventObserver.stop()
    isHovered = false

    if startedNetworkAgent {
      networkAgentClient.stop()
    }

    startedNetworkAgent = false
    clearNodes()
  }

  // MARK: - Publish

  /// Publishes the current Wi-Fi nodes.
  private func publish() {
    let snapshot = makeSnapshot()
    var nodes = renderer.makeNodes(snapshot: snapshot)
    if let rootIndex = nodes.firstIndex(where: { $0.id == rootID }) {
      nodes[rootIndex].contextMenu = WiFiContextMenu.make(config: sessionConfig)
    }
    applyNodes(nodes)
  }

  /// Returns the current render snapshot.
  private func makeSnapshot() -> Snapshot {
    let network = nativeWiFiStore.snapshot
    let presentation = WiFiPresentation(snapshot: network, config: sessionConfig)

    return Snapshot(
      config: sessionConfig,
      network: network,
      content: presentation.content,
      signalLevel: presentation.signalLevel,
      visualState: presentation.visualState,
      activeColorHex: presentation.activeColorHex,
      inactiveColorHex: presentation.inactiveColorHex,
      inlineContentVisible: shouldShowInlineContent(config: sessionConfig),
      detailsContentVisible: shouldShowDetailsContent(config: sessionConfig)
    )
  }
}

// MARK: - Events

extension WiFiNativeWidget {

  /// Handles app-wide Wi-Fi-related events.
  private func handleAppEvent(_ payload: EasyBarEventPayload) -> Bool {
    guard let event = payload.appEvent else { return false }

    switch event {
    case .networkChange:
      publish()
      return true
    default:
      return false
    }
  }

  /// Handles widget-local hover and context-menu events.
  private func handleWidgetEvent(_ payload: EasyBarEventPayload) {
    guard payload.widgetID == rootID else { return }
    guard let event = payload.widgetEvent else { return }

    if event == .contextMenuClicked, let actionID = payload.actionID {
      handleContextMenuAction(actionID)
      return
    }

    if NativeWidgetHoverSupport.updateHoverState(event, isHovered: &isHovered) {
      publish()
    }
  }

  /// Applies one persistent context-menu action.
  private func handleContextMenuAction(_ actionID: String) {
    guard let action = WiFiContextMenuAction(id: actionID) else { return }

    switch action {
    case .setMode(let mode):
      sessionConfig.mode = mode
      persistConfiguration()
    case .toggleField(let configKey):
      guard
        let field = BuiltinWiFiFieldCatalog.fields.first(where: {
          $0.configKey == configKey
        })
      else { return }
      sessionConfig.fields[keyPath: field.keyPath].toggle()
      persistConfiguration()
    case .refresh:
      networkAgentClient.refresh()
    case .openNetworkSettings:
      openNetworkSettings()
    }
  }

  private func persistConfiguration() {
    var edits = [
      TOMLEdit(
        path: ["builtins", "wifi", "content", "mode"],
        value: .string(sessionConfig.mode.rawValue)
      )
    ]
    edits.append(
      contentsOf: BuiltinWiFiFieldCatalog.fields.map { field in
        TOMLEdit(
          path: ["builtins", "wifi", "fields", field.configKey],
          value: .bool(sessionConfig.fields[keyPath: field.keyPath])
        )
      }
    )
    guard configPersistence.apply(edits) else {
      sessionConfig = configuredConfig
      publish()
      return
    }
    configuredConfig = sessionConfig
    publish()
  }

  /// Opens the macOS Network settings pane.
  private func openNetworkSettings() {
    guard let url = URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension")
    else { return }
    NSWorkspace.shared.open(url)
  }

  /// Returns whether inline content should be visible.
  private func shouldShowInlineContent(config: Config.WiFiBuiltinConfig) -> Bool {
    guard config.mode == .inline else { return false }

    switch config.surface {
    case .always:
      return true
    case .hover:
      return isHovered
    }
  }

  /// Returns whether details content should be presented while the widget is idle.
  private func shouldShowDetailsContent(config: Config.WiFiBuiltinConfig) -> Bool {
    guard config.mode == .details else { return false }
    return config.surface == .always
  }
}
