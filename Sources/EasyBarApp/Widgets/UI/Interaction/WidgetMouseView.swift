import AppKit
import EasyBarShared
import SwiftUI

let widgetHoverDelay: Duration = .milliseconds(80)

/// AppKit-backed event surface for widget mouse input.
struct WidgetMouseView: NSViewRepresentable {
  let widgetID: String
  let targetWidgetID: String
  let logger: ProcessLogger
  let eventHub: EventHub?
  let tracksHover: Bool
  let emitsMouseHover: Bool
  let emitsMouseDown: Bool
  let emitsMouseUp: Bool
  let emitsMouseClick: Bool
  let emitsMouseScroll: Bool
  let contextMenuItems: [WidgetContextMenuItem]?
  let onHoverChanged: ((Bool) -> Void)?

  init(
    widgetID: String,
    targetWidgetID: String? = nil,
    logger: ProcessLogger,
    eventHub: EventHub?,
    tracksHover: Bool = true,
    emitsMouseHover: Bool = false,
    emitsMouseDown: Bool = false,
    emitsMouseUp: Bool = false,
    emitsMouseClick: Bool = false,
    emitsMouseScroll: Bool = false,
    contextMenuItems: [WidgetContextMenuItem]? = nil,
    onHoverChanged: ((Bool) -> Void)? = nil
  ) {
    self.widgetID = widgetID
    self.targetWidgetID = targetWidgetID ?? widgetID
    self.logger = logger
    self.eventHub = eventHub
    self.tracksHover = tracksHover
    self.emitsMouseHover = emitsMouseHover
    self.emitsMouseDown = emitsMouseDown
    self.emitsMouseUp = emitsMouseUp
    self.emitsMouseClick = emitsMouseClick
    self.emitsMouseScroll = emitsMouseScroll
    self.contextMenuItems = contextMenuItems
    self.onHoverChanged = onHoverChanged
  }

  /// Creates the AppKit-backed mouse surface.
  func makeNSView(context: Context) -> MouseTrackingNSView {
    let view = MouseTrackingNSView(logger: logger)
    view.eventHub = eventHub
    view.widgetID = widgetID
    view.targetWidgetID = targetWidgetID
    view.tracksHover = tracksHover
    view.emitsMouseHover = emitsMouseHover
    view.emitsMouseDown = emitsMouseDown
    view.emitsMouseUp = emitsMouseUp
    view.emitsMouseClick = emitsMouseClick
    view.emitsMouseScroll = emitsMouseScroll
    view.contextMenuItems = contextMenuItems
    view.onHoverChanged = onHoverChanged
    return view
  }

  /// Updates the AppKit surface ids and interaction flags.
  func updateNSView(_ nsView: MouseTrackingNSView, context: Context) {
    nsView.updateHoverIdentity(
      widgetID: widgetID,
      targetWidgetID: targetWidgetID,
      tracksHover: tracksHover
    )
    nsView.emitsMouseHover = emitsMouseHover
    nsView.emitsMouseDown = emitsMouseDown
    nsView.emitsMouseUp = emitsMouseUp
    nsView.emitsMouseClick = emitsMouseClick
    nsView.emitsMouseScroll = emitsMouseScroll
    nsView.contextMenuItems = contextMenuItems
    nsView.onHoverChanged = onHoverChanged
    nsView.eventHub = eventHub
  }

  /// Releases hover ownership when SwiftUI removes the backing AppKit view.
  static func dismantleNSView(_ nsView: MouseTrackingNSView, coordinator: Void) {
    nsView.prepareForRemoval()
  }
}

final class MouseTrackingNSView: NSView {
  var widgetID: String = ""
  var targetWidgetID: String = ""
  let logger: ProcessLogger
  var eventHub: EventHub?
  var tracksHover = true
  var emitsMouseHover = false
  var emitsMouseDown = false
  var emitsMouseUp = false
  var emitsMouseClick = false
  var emitsMouseScroll = false
  var contextMenuItems: [WidgetContextMenuItem]?
  var onContextMenuAction: ((String) -> Void)?
  var onHoverChanged: ((Bool) -> Void)?

  private var trackingArea: NSTrackingArea?
  private var isMouseInside = false
  private let hoverSurfaceID = UUID()
  private static let hoverState = WidgetHoverState()

  init(logger: ProcessLogger) {
    self.logger = logger
    super.init(frame: .zero)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  /// Accept the first click even when EasyBar is not active.
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    true
  }

  /// Keep the view eligible for responder handling.
  override var acceptsFirstResponder: Bool {
    true
  }

  /// Make this transparent view participate in hit-testing only when it actually needs to
  /// consume button or scroll events. Hover tracking uses `NSTrackingArea` and does not need
  /// to win hit-testing.
  override func hitTest(_ point: NSPoint) -> NSView? {
    guard bounds.contains(point) else { return nil }
    if handlesMouseEvents {
      return self
    }
    guard consumesRightClickWithContextMenu else { return nil }
    switch NSApp?.currentEvent?.type {
    case .rightMouseDown, .rightMouseUp:
      return self
    default:
      return nil
    }
  }

  /// Returns whether ordinary mouse handlers require direct event ownership.
  private var handlesMouseEvents: Bool {
    return emitsMouseDown || emitsMouseUp || emitsMouseClick || emitsMouseScroll
  }

  var consumesRightClickWithContextMenu: Bool {
    contextMenuItems?.isEmpty == false
  }

  /// Rebuilds tracking areas after layout updates.
  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    replaceTrackingArea()
  }

  /// Emits hover-entered when tracking is enabled.
  override func mouseEntered(with event: NSEvent) {
    beginHoverIfNeeded()
  }

  /// Updates hover identity without leaving registrations under an old node ID.
  func updateHoverIdentity(widgetID: String, targetWidgetID: String, tracksHover: Bool) {
    let identityChanged = self.targetWidgetID != targetWidgetID
    let shouldRestartHover = isMouseInside && (identityChanged || !tracksHover)

    if shouldRestartHover {
      endHover(immediately: true)
    }

    self.widgetID = widgetID
    self.targetWidgetID = targetWidgetID
    self.tracksHover = tracksHover

    if identityChanged, tracksHover, isMouseCurrentlyInside {
      beginHoverIfNeeded()
    }
  }

  /// Releases any active hover registration before this view is dismantled.
  func prepareForRemoval() {
    endHover(immediately: true)
    onHoverChanged = nil
    onContextMenuAction = nil
  }

  /// Begins hover tracking for this concrete AppKit surface.
  private func beginHoverIfNeeded() {
    guard tracksHover else { return }
    guard !isMouseInside else { return }
    isMouseInside = true
    guard Self.hoverState.enter(widgetID: targetWidgetID, surfaceID: hoverSurfaceID) else { return }

    onHoverChanged?(true)

    if emitsMouseHover {
      emitMouseEvent(.mouseEntered)
    }
  }

  /// Emits hover-exited when tracking is enabled.
  override func mouseExited(with event: NSEvent) {
    endHover(immediately: false)
  }

  /// Ends hover tracking and emits an aggregate exit when this was the last surface.
  private func endHover(immediately: Bool) {
    guard isMouseInside else { return }
    isMouseInside = false

    let handler = hoverExitHandler()
    if immediately {
      if Self.hoverState.remove(widgetID: targetWidgetID, surfaceID: hoverSurfaceID) {
        handler()
      }
      return
    }

    Self.hoverState.exit(
      widgetID: targetWidgetID,
      surfaceID: hoverSurfaceID,
      handler: handler
    )
  }

  /// Captures the current callbacks and identifiers for a delayed hover exit.
  private func hoverExitHandler() -> @MainActor @Sendable () -> Void {
    let onHoverChanged = onHoverChanged
    let emitsMouseHover = emitsMouseHover
    let widgetID = widgetID
    let targetWidgetID = targetWidgetID

    return {
      onHoverChanged?(false)
      guard emitsMouseHover else { return }
      WidgetEventDispatcher.shared.enqueue {
        await self.eventHub?.emitWidgetEvent(
          .mouseExited,
          widgetID: widgetID,
          targetWidgetID: targetWidgetID
        )
      }
    }
  }

  /// Returns whether the window cursor is currently inside this view.
  private var isMouseCurrentlyInside: Bool {
    guard window != nil else { return false }
    return bounds.contains(convert(window?.mouseLocationOutsideOfEventStream ?? .zero, from: nil))
  }

  /// Emits a left-button mouse-down event.
  override func mouseDown(with event: NSEvent) {
    emitMouseDown(button: .left)
  }

  /// Emits a left-button mouse-up and clicked event.
  override func mouseUp(with event: NSEvent) {
    emitMouseUp(button: .left)
  }

  /// Emits a right-button mouse-down event.
  override func rightMouseDown(with event: NSEvent) {
    if let menu = makeContextMenu() {
      NSMenu.popUpContextMenu(menu, with: event, for: self)
      return
    }
    emitMouseDown(button: .right)
  }

  /// Emits a right-button mouse-up and clicked event.
  override func rightMouseUp(with event: NSEvent) {
    guard !consumesRightClickWithContextMenu else { return }
    emitMouseUp(button: .right)
  }

  /// Builds the current native menu from immutable rendered-node state.
  func makeContextMenu() -> NSMenu? {
    guard let contextMenuItems, !contextMenuItems.isEmpty else { return nil }
    let menu = NSMenu()
    appendContextMenuItems(contextMenuItems, to: menu)
    return menu.items.isEmpty ? nil : menu
  }

  private func appendContextMenuItems(_ entries: [WidgetContextMenuItem], to menu: NSMenu) {
    for entry in entries {
      if entry.separator {
        menu.addItem(.separator())
        continue
      }

      guard let title = entry.title, !title.isEmpty else { continue }
      let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
      if let submenu = entry.submenu, !submenu.isEmpty {
        let childMenu = NSMenu(title: title)
        appendContextMenuItems(submenu, to: childMenu)
        guard !childMenu.items.isEmpty else { continue }
        item.submenu = childMenu
      } else if let actionID = entry.id, !actionID.isEmpty {
        item.action = #selector(contextMenuItemSelected(_:))
        item.target = self
        item.representedObject = actionID
        item.isEnabled = entry.enabled
        item.state = entry.checked ? .on : .off
      } else {
        continue
      }
      menu.addItem(item)
    }
  }

  @objc private func contextMenuItemSelected(_ sender: NSMenuItem) {
    handleContextMenuItemSelection(sender)
  }

  func handleContextMenuItemSelection(_ sender: NSMenuItem) {
    guard sender.isEnabled, let actionID = sender.representedObject as? String else { return }
    if let onContextMenuAction {
      onContextMenuAction(actionID)
      return
    }
    let eventWidgetID = widgetID
    let eventTargetWidgetID = targetWidgetID
    let eventHub = eventHub
    WidgetEventDispatcher.shared.enqueue {
      await eventHub?.emitWidgetEvent(
        .contextMenuClicked,
        widgetID: eventWidgetID,
        targetWidgetID: eventTargetWidgetID,
        actionID: actionID
      )
    }
  }

  /// Emits a middle-button mouse-down event.
  override func otherMouseDown(with event: NSEvent) {
    emitMouseDown(button: .middle)
  }

  /// Emits a middle-button mouse-up and clicked event.
  override func otherMouseUp(with event: NSEvent) {
    emitMouseUp(button: .middle)
  }

  /// Emits one scroll-wheel event.
  override func scrollWheel(with event: NSEvent) {
    guard emitsMouseScroll else { return }

    let eventWidgetID = widgetID
    let eventTargetWidgetID = targetWidgetID
    let deltaX = Double(event.scrollingDeltaX)
    let deltaY = Double(event.scrollingDeltaY)
    guard deltaY.isFinite, deltaY != 0 else { return }
    let direction: ScrollDirection = deltaY > 0 ? .up : .down

    logger.debug(
      "mouse scrolled",
      .field("widget", "\(eventWidgetID)"),
      .field("direction", "\(direction.rawValue)"),
    )

    WidgetEventDispatcher.shared.enqueue {
      await self.eventHub?.emitWidgetEvent(
        .mouseScrolled,
        widgetID: eventWidgetID,
        targetWidgetID: eventTargetWidgetID,
        direction: direction,
        deltaX: deltaX,
        deltaY: deltaY
      )
    }
  }

  /// Replaces the current tracking area with the standard widget mouse options.
  private func replaceTrackingArea() {
    removeTrackingAreaIfNeeded()
    guard tracksHover else { return }

    let area = NSTrackingArea(
      rect: .zero,
      options: trackingOptions,
      owner: self,
      userInfo: nil
    )
    addTrackingArea(area)
    trackingArea = area
  }

  /// Removes the current tracking area when present.
  private func removeTrackingAreaIfNeeded() {
    guard let trackingArea else { return }
    removeTrackingArea(trackingArea)
    self.trackingArea = nil
  }

  /// Returns the tracking options used for widget mouse handling.
  private var trackingOptions: NSTrackingArea.Options {
    [
      .mouseEnteredAndExited,
      .mouseMoved,
      .activeAlways,
      .inVisibleRect,
    ]
  }

  /// Emits one mouse down event for the given button.
  private func emitMouseDown(button: MouseButton) {
    guard emitsMouseDown else { return }
    emitMouseEvent(.mouseDown, button: button)
  }

  /// Emits one mouse up and click pair for the given button.
  private func emitMouseUp(button: MouseButton) {
    if emitsMouseUp {
      emitMouseEvent(.mouseUp, button: button)
    }

    if emitsMouseClick {
      emitMouseEvent(.mouseClicked, button: button)
    }
  }

  /// Emits one widget mouse event with shared logging.
  private func emitMouseEvent(_ event: WidgetEvent, button: MouseButton? = nil) {
    let eventWidgetID = widgetID
    let eventTargetWidgetID = targetWidgetID
    let buttonSuffix = button.map { " button=\($0.rawValue)" } ?? ""
    logger.debug(
      "emit mouse event",
      .field("event", "\(event.rawValue)"),
      .field("widget", "\(eventWidgetID)"),
      .field("target", "\(eventTargetWidgetID)\(buttonSuffix)"),
    )

    WidgetEventDispatcher.shared.enqueue {
      await self.eventHub?.emitWidgetEvent(
        event,
        widgetID: eventWidgetID,
        targetWidgetID: eventTargetWidgetID,
        button: button
      )
    }
  }
}

/// Tracks hover state across delayed exit tasks.
///
/// Sendability is guarded by `LockedState`; hovered IDs and pending exit tasks
/// are only accessed while holding that lock.
final class WidgetHoverState: @unchecked Sendable {
  private struct State {
    var surfaceIDsByWidgetID: [String: Set<UUID>] = [:]
    var pendingExitTasks: [String: Task<Void, Never>] = [:]
  }

  private let state = LockedState(State())

  /// Marks one widget as hovered and returns whether it was newly entered.
  func enter(widgetID: String, surfaceID: UUID) -> Bool {
    state.withLock { state in
      state.pendingExitTasks[widgetID]?.cancel()
      state.pendingExitTasks[widgetID] = nil
      let wasEmpty = state.surfaceIDsByWidgetID[widgetID]?.isEmpty != false
      state.surfaceIDsByWidgetID[widgetID, default: []].insert(surfaceID)
      return wasEmpty
    }
  }

  /// Removes one concrete surface and returns whether aggregate hover ended.
  func remove(widgetID: String, surfaceID: UUID) -> Bool {
    state.withLock { state in
      guard state.surfaceIDsByWidgetID[widgetID]?.remove(surfaceID) != nil else { return false }
      guard state.surfaceIDsByWidgetID[widgetID]?.isEmpty == true else { return false }
      state.surfaceIDsByWidgetID.removeValue(forKey: widgetID)
      state.pendingExitTasks[widgetID]?.cancel()
      state.pendingExitTasks[widgetID] = nil
      return true
    }
  }

  /// Delays the hover-exit slightly so overlapping surfaces do not flicker.
  func exit(
    widgetID: String,
    surfaceID: UUID,
    handler: @escaping @MainActor @Sendable () -> Void
  ) {
    let shouldSchedule = state.withLock { state -> Bool in
      guard state.surfaceIDsByWidgetID[widgetID]?.remove(surfaceID) != nil else { return false }
      guard state.surfaceIDsByWidgetID[widgetID]?.isEmpty == true else { return false }
      state.surfaceIDsByWidgetID.removeValue(forKey: widgetID)
      return true
    }
    guard shouldSchedule else { return }

    let task = Task { [weak self] in
      do {
        try await Task.sleep(for: widgetHoverDelay)
      } catch {
        return
      }

      guard let self else { return }
      let shouldEmit = self.state.withLock { state -> Bool in
        let shouldEmit = state.surfaceIDsByWidgetID[widgetID]?.isEmpty != false
        state.pendingExitTasks[widgetID] = nil
        return shouldEmit
      }

      guard shouldEmit else { return }
      await MainActor.run {
        handler()
      }
    }

    let oldTask = state.withLock { state -> Task<Void, Never>? in
      let oldTask = state.pendingExitTasks[widgetID]
      state.pendingExitTasks[widgetID] = task
      return oldTask
    }

    oldTask?.cancel()
  }
}
