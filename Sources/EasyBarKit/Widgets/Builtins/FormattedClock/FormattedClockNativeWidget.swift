import Foundation

/// Native widget that renders one formatted timestamp.
@MainActor
final class FormattedClockNativeWidget: NativeWidget {

  let rootID: String
  let widgetStore: WidgetStore

  private let placement: Config.BuiltinWidgetPlacement
  private let style: Config.BuiltinWidgetStyle
  private let format: String
  private let eventObserver: EasyBarEventObserver
  private let formatterCache = FormattedDateFormatterCache()

  init(
    rootID: String,
    widgetStore: WidgetStore,
    eventHub: EventHub,
    placement: Config.BuiltinWidgetPlacement,
    style: Config.BuiltinWidgetStyle,
    format: String
  ) {
    self.rootID = rootID
    self.widgetStore = widgetStore
    self.eventObserver = EasyBarEventObserver(eventHub: eventHub)
    self.placement = placement
    self.style = style
    self.format = format
  }

  var appEventSubscriptions: Set<String> {
    [
      refreshEvent.rawValue,
      AppEvent.systemWoke.rawValue,
    ]
  }

  /// Starts observing clock refresh events.
  func start() {
    eventObserver.start(eventNames: appEventSubscriptions) { [weak self] payload in
      guard let self else { return }
      guard let event = payload.appEvent else { return }
      guard event == self.refreshEvent || event == .systemWoke else { return }
      self.publish()
    }

    publish()
  }

  /// Stops observing events and clears the rendered node.
  func stop() {
    eventObserver.stop()
    clearNodes()
  }

  private var refreshEvent: AppEvent {
    return FormattedClockRefreshPolicy.event(for: format)
  }

  /// Publishes the current formatted timestamp.
  private func publish() {
    let node = BuiltinNativeNodeFactory.makeItemNode(
      rootID: rootID,
      placement: placement,
      style: style,
      text: formatterCache.string(from: Date(), format: format)
    )

    applyNodes([node])
  }
}
