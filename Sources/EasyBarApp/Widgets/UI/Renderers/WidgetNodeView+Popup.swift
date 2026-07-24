import SwiftUI

private enum PopupContentKind {
  case none
  case calendarUpcoming
  case calendarMonth
  case inbox
  case genericNodePopup
}

// MARK: - Popup State

extension WidgetNodeView {
  var nodeColor: Color {
    return color(node.color)
  }

  /// Resolves an optional hex color or falls back to the default text color.
  func color(_ hex: String?) -> Color {
    guard let hex, !hex.isEmpty else {
      return Theme.defaultTextColor(snapshot: configStore.snapshot)
    }

    return Color(hex: hex, snapshot: configStore.snapshot)
  }

  /// Returns a system font for an optional point size.
  func fontValue(size: Double?) -> Font? {
    guard let size else { return nil }
    return .system(size: WidgetRenderMetrics.positive(size, fallback: 12))
  }

  /// Converts an optional `Double` into an optional `CGFloat`.
  func cgFloat(_ value: Double?) -> CGFloat? {
    guard let value else { return nil }
    return CGFloat(value)
  }

  /// Schedules a delayed popup close check.
  func schedulePopupCloseCheck() {
    cancelPopupCloseCheck()
    popupCloseTask = Task { @MainActor in
      do {
        try await Task.sleep(nanoseconds: widgetHoverDelayNanoseconds)
      } catch {
        return
      }
      popupCloseTask = nil
      closePopupIfIdle()
    }
  }

  /// Cancels the pending popup close check, if any.
  func cancelPopupCloseCheck() {
    popupCloseTask?.cancel()
    popupCloseTask = nil
  }

  /// Updates popup presentation from anchor hover state.
  func handleAnchorHover(_ hovering: Bool) {
    anchorHovered = hovering

    if hovering {
      cancelPopupCloseCheck()
      guard nodeCanPresentPopup else { return }
      popupPresented = true
      return
    }

    schedulePopupCloseCheck()
  }

  /// Updates popup presentation from popup hover state.
  func handlePopupHover(_ hovering: Bool) {
    popupHovered = hovering

    guard !hovering else {
      cancelPopupCloseCheck()
      return
    }
    schedulePopupCloseCheck()
  }

  /// Closes the popup when neither anchor nor content is hovered.
  func closePopupIfIdle() {
    guard !node.presentsPopupAutomatically else { return }
    guard !popupPanel.hasTransientInteraction else { return }
    guard !anchorHovered else { return }
    guard !popupHovered else { return }
    popupPresented = false
  }

  /// Synchronizes the AppKit popup panel with SwiftUI state.
  func updatePopupPanel(isPresented: Bool) {
    guard nodeCanPresentPopup else {
      popupPanel.close()
      return
    }

    popupPanel.update(isPresented: isPresented, content: popupPanelContent)
  }
}

// MARK: - Layout Data

extension WidgetNodeView {
  var childRow: some View {
    HStack(spacing: stackSpacing) {
      ForEach(children) { child in
        WidgetNodeView(node: child, logger: logger)
      }
    }
  }

  var stackSpacing: CGFloat {
    return CGFloat(node.spacing ?? 6)
  }

  var itemSpacing: CGFloat {
    return CGFloat(node.spacing ?? 4)
  }

  var currentValue: Double {
    return node.value ?? 0
  }

  var minValue: Double {
    return node.min ?? 0
  }

  var maxValue: Double {
    return node.max ?? 100
  }

  var stepValue: Double {
    return node.step ?? 1
  }

  var progressWidth: CGFloat {
    return WidgetRenderMetrics.nonnegative(node.width, fallback: 64)
  }

  var progressHeight: CGFloat {
    return WidgetRenderMetrics.nonnegative(node.height, fallback: 8)
  }

  var sparklineWidth: CGFloat {
    return WidgetRenderMetrics.nonnegative(node.width, fallback: 64)
  }

  var sparklineHeight: CGFloat {
    return WidgetRenderMetrics.nonnegative(node.height, fallback: 18)
  }

  var sparklineLineWidth: CGFloat {
    return WidgetRenderMetrics.nonnegative(node.lineWidth, fallback: 1.5)
  }

  var nodeWidth: CGFloat? {
    return WidgetRenderMetrics.dimension(node.width)
  }

  var children: [WidgetNodeState] {
    return store.children(of: node.id)
  }

  var anchorChildren: [WidgetNodeState] {
    return store.anchorChildren(of: node.id)
  }

  var popupChildren: [WidgetNodeState] {
    return store.popupChildren(of: node.id)
  }

  var hasAnchorChildren: Bool {
    return !anchorChildren.isEmpty
  }

  var hasPopupChildren: Bool {
    return !popupChildren.isEmpty
  }

  var nodeCanPresentPopup: Bool {
    return popupContentKind != .none
  }

  var usesNativePopupAnchor: Bool {
    switch popupContentKind {
    case .calendarUpcoming, .calendarMonth, .inbox: return true
    case .none, .genericNodePopup: return false
    }
  }

  var popupHoverBackground: some View {
    PopupHoverRegion { hovering in handlePopupHover(hovering) }
  }

  var popupPanelContent: AnyView {
    switch popupContentKind {
    case .none:
      return AnyView(EmptyView())
    case .calendarUpcoming:
      guard let appViewServices else { return AnyView(EmptyView()) }
      return AnyView(
        NativeUpcomingCalendarPopupView(services: appViewServices)
          .environmentObject(configStore)
          .background(popupHoverBackground)
      )
    case .calendarMonth:
      guard let appViewServices else { return AnyView(EmptyView()) }
      return AnyView(
        NativeMonthCalendarPopupView(services: appViewServices)
          .environmentObject(configStore)
          .background(popupHoverBackground)
      )
    case .inbox:
      guard let appViewServices else { return AnyView(EmptyView()) }
      return AnyView(
        InboxPopupView(
          store: appViewServices.inboxStore,
          eventHub: appViewServices.eventHub,
          popupPanel: popupPanel,
          onSourceActionsMenuClosed: schedulePopupCloseCheck
        )
        .environmentObject(configStore)
        .background(popupHoverBackground)
      )
    case .genericNodePopup:
      guard let appViewServices else { return AnyView(EmptyView()) }
      return AnyView(
        popupContent
          .environmentObject(configStore)
          .environmentObject(store)
          .environment(\.appViewServices, appViewServices)
          .background(popupHoverBackground)
      )
    }
  }

  private var popupContentKind: PopupContentKind {
    if node.isInboxRoot { return .inbox }
    if node.isCalendarRoot {
      switch configStore.snapshot.builtins.calendar.popupMode {
      case .none: return .none
      case .upcoming: return .calendarUpcoming
      case .month: return .calendarMonth
      }
    }

    return node.kind == .popup || hasPopupChildren ? .genericNodePopup : .none
  }

  var nodeStyle: WidgetNodeStyle {
    return WidgetNodeStyle(node: node)
  }
}
