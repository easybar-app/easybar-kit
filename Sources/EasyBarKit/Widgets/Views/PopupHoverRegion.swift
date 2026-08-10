import AppKit
import SwiftUI

struct PopupHoverRegion: NSViewRepresentable {

  let onHoverChanged: (Bool) -> Void

  /// Creates the AppKit hover region.
  func makeNSView(context: Context) -> PopupHoverNSView {
    let view = PopupHoverNSView()
    view.hoverChanged = onHoverChanged
    return view
  }

  /// Updates the AppKit hover callback.
  func updateNSView(_ nsView: PopupHoverNSView, context: Context) {
    nsView.hoverChanged = onHoverChanged
  }

  /// Clears popup hover state when SwiftUI removes the panel content.
  static func dismantleNSView(_ nsView: PopupHoverNSView, coordinator: Void) {
    nsView.prepareForRemoval()
  }
}

final class PopupHoverNSView: NSView {

  var hoverChanged: ((Bool) -> Void)?
  private var trackingArea: NSTrackingArea?
  private var isMouseInside = false

  /// Keep this view out of hit-testing so it never steals clicks or scroll events.
  override func hitTest(_ point: NSPoint) -> NSView? {
    nil
  }

  /// Rebuilds tracking areas after bounds changes.
  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    replaceTrackingArea()
  }

  /// Emits hover-entered to SwiftUI.
  override func mouseEntered(with event: NSEvent) {
    guard !isMouseInside else { return }
    isMouseInside = true
    hoverChanged?(true)
  }

  /// Emits hover-exited to SwiftUI.
  override func mouseExited(with event: NSEvent) {
    guard isMouseInside else { return }
    isMouseInside = false
    hoverChanged?(false)
  }

  /// Emits the matching exit callback if the region disappears while hovered.
  func prepareForRemoval() {
    if isMouseInside {
      isMouseInside = false
      hoverChanged?(false)
    }
    hoverChanged = nil
  }

  /// Replaces the current tracking area with the standard hover configuration.
  private func replaceTrackingArea() {
    removeTrackingAreaIfNeeded()

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

  /// Returns the hover tracking options used by the popup region.
  private var trackingOptions: NSTrackingArea.Options {
    [
      .mouseEnteredAndExited,
      .activeAlways,
      .inVisibleRect,
    ]
  }
}
