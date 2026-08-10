import Combine
import EasyBarShared
import SwiftUI

/// Public presentation snapshot used by EasyBar frontends.
///
/// The model intentionally exposes rendered widget surfaces instead of the internal
/// widget tree. This keeps the Lua/runtime implementation in EasyBarKit while allowing
/// multiple hosts to present the same widgets in different macOS surfaces.
@MainActor
public final class EasyBarPresentationModel: ObservableObject {
  /// Immutable bar appearance needed by the custom EasyBar window frontend.
  public struct BarStyle {
    public let height: CGFloat
    public let paddingX: CGFloat
    public let extendBehindNotch: Bool
    public let background: Color
    public let border: Color
    public let drawsBorder: Bool
    public let text: Color

    fileprivate init(snapshot: ConfigSnapshot) {
      self.height = snapshot.bar.height
      self.paddingX = snapshot.bar.paddingX
      self.extendBehindNotch = snapshot.bar.extendBehindNotch
      self.background = Theme.barBackground(snapshot: snapshot)
      self.border = Theme.barBorder(snapshot: snapshot)
      self.drawsBorder = !snapshot.bar.borderHex.isFullyTransparentHexColor
      self.text = Theme.defaultTextColor(snapshot: snapshot)
    }
  }

  /// One top-level surface rendered by EasyBarKit.
  ///
  /// Scripted surfaces come from Lua widgets. EasyBarKit may also publish host-owned built-in
  /// surfaces selected by the frontend's `EasyBarBuiltInSurfacePolicy`.
  public struct WidgetSurface: Identifiable {
    public let id: String
    public let position: EasyBarShared.WidgetPosition
    public let order: Int

    fileprivate let content: AnyView

    /// Returns a self-contained SwiftUI view for this widget.
    @MainActor
    public func makeView() -> AnyView {
      content
    }
  }

  /// Current custom-bar appearance.
  @Published public private(set) var barStyle: BarStyle
  /// Current top-level widget surfaces, sorted exactly like the runtime widget store.
  @Published public private(set) var widgets: [WidgetSurface] = []

  private let logger: ProcessLogger
  private let configStore: ConfigSnapshotStore
  private let widgetStore: WidgetStore
  private let aeroSpaceService: AeroSpaceService
  private let appViewServices: AppViewServices
  private var cancellables = Set<AnyCancellable>()

  init(logger: ProcessLogger, services: AppServices) {
    self.logger = logger
    self.configStore = services.configSnapshotStore
    self.widgetStore = services.widgetStore
    self.aeroSpaceService = services.aeroSpaceService
    self.appViewServices = AppViewServices(
      eventHub: services.eventHub,
      inboxStore: services.inboxStore,
      monthCalendarStore: services.nativeMonthCalendarStore,
      upcomingCalendarStore: services.nativeUpcomingCalendarStore,
      composerCalendarStore: services.nativeComposerCalendarStore,
      monthCalendarClient: services.monthCalendarAgentClient,
      upcomingCalendarClient: services.upcomingCalendarAgentClient,
      composerCalendarClient: services.composerCalendarAgentClient
    )
    self.barStyle = BarStyle(snapshot: services.configSnapshotStore.snapshot)

    services.widgetStore.$nodes
      .sink { [weak self] _ in
        self?.rebuildWidgets()
      }
      .store(in: &cancellables)

    services.configSnapshotStore.$snapshot
      .sink { [weak self] snapshot in
        guard let self else { return }
        self.barStyle = BarStyle(snapshot: snapshot)
        self.rebuildWidgets()
      }
      .store(in: &cancellables)

    rebuildWidgets()
  }

  /// Returns the top-level widgets assigned to one logical EasyBar position.
  public func widgets(at position: EasyBarShared.WidgetPosition) -> [WidgetSurface] {
    widgets.filter { $0.position == position }
  }

  /// Rebuilds public widget surfaces from the internal immutable node snapshots.
  private func rebuildWidgets() {
    var result: [WidgetSurface] = []

    for position in WidgetPosition.allCases {
      for node in widgetStore.topLevelNodes(for: position) {
        let view = AnyView(
          WidgetNodeView(node: node, logger: logger)
            .environmentObject(configStore)
            .environmentObject(widgetStore)
            .environmentObject(aeroSpaceService)
            .environment(\.appViewServices, appViewServices)
        )

        result.append(
          WidgetSurface(
            id: node.id,
            position: node.position,
            order: node.order,
            content: view
          )
        )
      }
    }

    widgets = result
  }
}
