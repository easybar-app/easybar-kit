import AppKit
import Combine
import EasyBarCalendarUI
import EasyBarShared
import SwiftUI

/// Borderless composer panel that can still become key for text editing.
private final class CalendarEventComposerPanel: NSPanel {
  /// Allows text fields, pickers, and buttons inside the borderless panel to become active.
  override var canBecomeKey: Bool {
    true
  }

  /// Allows the composer panel to behave like the active editing window.
  override var canBecomeMain: Bool {
    true
  }
}

/// Manages a floating panel for the shared calendar event composer.
@MainActor
final class CalendarEventComposerPanelController: ObservableObject {
  private var panel: NSPanel?
  private var hostingController = NSHostingController(rootView: AnyView(EmptyView()))
  private var composer: CalendarEventComposer?
  private let dependencies: CalendarEventComposerDependencies

  /// Creates one composer panel controller with explicit dependencies.
  init(dependencies: CalendarEventComposerDependencies) {
    self.dependencies = dependencies
  }

  /// Creates the app-wired composer panel used by calendar popup adapters.
  convenience init(services: AppViewServices) {
    self.init(dependencies: .live(services: services))
  }

  /// Presents the composer panel for one new appointment.
  func present(
    defaultDate: Date,
    config: Config.CalendarBuiltinConfig,
    onChanged: @escaping () -> Void
  ) {
    let composer = makeComposer(config: config)
    composer.prepare(defaultDate: defaultDate)
    present(composer: composer, config: config, onChanged: onChanged)
  }

  /// Presents the composer panel for one existing appointment.
  func present(
    event: CalendarAgentEvent,
    config: Config.CalendarBuiltinConfig,
    onChanged: @escaping () -> Void
  ) {
    let composer = makeComposer(config: config)
    composer.prepare(event: event)
    present(composer: composer, config: config, onChanged: onChanged)
  }

  /// Closes the composer panel when present.
  func close() {
    panel?.close()
    panel = nil
    composer = nil
    hostingController = NSHostingController(rootView: AnyView(EmptyView()))
  }

  /// Installs one prepared composer into the shared hosting controller and shows the panel.
  private func present(
    composer: CalendarEventComposer,
    config: Config.CalendarBuiltinConfig,
    onChanged: @escaping () -> Void
  ) {
    self.composer = composer
    hostingController.rootView = AnyView(
      CalendarEventComposerView(
        composer: composer,
        config: config.calendarComposerUIConfig,
        appointmentsStyle: config.appointmentsCalendarUIStyle,
        onCancel: { [weak self] in
          self?.close()
        },
        onSaved: { [weak self] in
          onChanged()
          self?.close()
        },
        onDeleted: { [weak self] in
          onChanged()
          self?.close()
        }
      )
    )

    showIfPossible()
  }

  /// Shows the panel centered relative to the active window or screen.
  private func showIfPossible() {
    let panel = panel ?? makePanel()
    self.panel = panel

    if let composer {
      panel.title = composer.panelTitle
    }

    hostingController.view.layoutSubtreeIfNeeded()
    let fittingSize = hostingController.view.fittingSize
    guard fittingSize.width > 0, fittingSize.height > 0 else { return }

    panel.setContentSize(fittingSize)

    if let parentWindow = NSApp.keyWindow ?? NSApp.mainWindow {
      let parentFrame = parentWindow.frame
      panel.setFrameOrigin(
        NSPoint(
          x: parentFrame.midX - fittingSize.width / 2,
          y: parentFrame.midY - fittingSize.height / 2
        )
      )
    } else if let screenFrame = NSScreen.main?.visibleFrame {
      panel.setFrameOrigin(
        NSPoint(
          x: screenFrame.midX - fittingSize.width / 2,
          y: screenFrame.midY - fittingSize.height / 2
        )
      )
    }

    panel.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  /// Builds the shared floating composer panel.
  private func makePanel() -> NSPanel {
    let panel = CalendarEventComposerPanel(
      contentRect: .zero,
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )

    panel.title = "Appointment"
    panel.isMovableByWindowBackground = true
    panel.isFloatingPanel = true
    panel.level = .floating
    panel.hasShadow = true
    panel.hidesOnDeactivate = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.contentViewController = hostingController

    panel.contentView?.wantsLayer = true
    panel.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
    panel.contentView?.layer?.masksToBounds = false

    return panel
  }

  /// Builds one reusable composer view model wired to a fresh composer-only calendar source.
  private func makeComposer(config: Config.CalendarBuiltinConfig) -> CalendarEventComposer {
    CalendarEventComposer(
      config: config.calendarComposerUIConfig,
      snapshotPublisher: dependencies.snapshotPublisher,
      refreshSnapshots: dependencies.refreshSnapshots,
      createEvent: dependencies.createEvent,
      updateEvent: dependencies.updateEvent,
      deleteEvent: dependencies.deleteEvent,
      openCalendarApp: dependencies.openCalendarApp
    )
  }
}
