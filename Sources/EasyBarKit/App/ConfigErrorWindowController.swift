import AppKit
import EasyBarShared
import SwiftUI

/// Presents a floating window that explains config load or reload failures.
@MainActor
final class ConfigErrorWindowController: NSObject, NSWindowDelegate {
  /// Currently presented config error window.
  private var window: NSWindow?
  /// Hosting controller reused for the error content view.
  private var hostingController = NSHostingController(rootView: AnyView(EmptyView()))

  /// Presents the current config failure state in a dedicated floating window.
  func present(
    failureState: Config.LoadFailureState,
    configPath: String,
    onReload: @escaping () -> Void
  ) {
    present(
      makePresentation(failureState: failureState, configPath: configPath),
      configPath: configPath,
      onReload: onReload
    )
  }

  /// Presents non-fatal config warnings in the same floating issue window.
  func present(
    warnings: [String],
    configPath: String,
    onReload: @escaping () -> Void
  ) {
    guard !warnings.isEmpty else {
      close()
      return
    }

    present(
      makeWarningPresentation(warnings: warnings, configPath: configPath),
      configPath: configPath,
      onReload: onReload
    )
  }

  /// Presents one prepared config issue model.
  private func present(
    _ presentation: SharedConfigErrorPresentation,
    configPath: String,
    onReload: @escaping () -> Void
  ) {
    hostingController.rootView = AnyView(
      SharedConfigErrorView(
        presentation: presentation,
        onOpen: {
          NSWorkspace.shared.open(URL(fileURLWithPath: configPath))
        },
        onRetry: onReload,
        onClose: { [weak self] in
          self?.close()
        }
      )
    )

    let window = window ?? makeWindow()
    self.window = window

    window.title = presentation.windowTitle
    hostingController.view.layoutSubtreeIfNeeded()
    let fittingSize = hostingController.view.fittingSize
    guard fittingSize.width > 0, fittingSize.height > 0 else { return }

    window.setContentSize(fittingSize)
    center(window: window, size: fittingSize)
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  /// Closes the config error window when it is currently shown.
  func close() {
    window?.close()
    window = nil
    hostingController = NSHostingController(rootView: AnyView(EmptyView()))
  }

  /// Builds the floating config error window shell.
  private func makeWindow() -> NSWindow {
    let window = NSWindow(
      contentRect: .zero,
      styleMask: [.titled, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    window.title = "EasyBar Config Error"
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.isMovableByWindowBackground = true
    window.level = .floating
    window.hasShadow = true
    window.isReleasedWhenClosed = false
    window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
    window.backgroundColor = .clear
    window.isOpaque = false
    window.representedURL = nil
    window.miniwindowImage = NSApp.applicationIconImage
    window.standardWindowButton(.closeButton)?.isHidden = true
    window.standardWindowButton(.miniaturizeButton)?.isHidden = true
    window.standardWindowButton(.zoomButton)?.isHidden = true
    window.standardWindowButton(.documentIconButton)?.image = NSApp.applicationIconImage
    window.contentViewController = hostingController
    window.delegate = self
    return window
  }

  /// Centers the floating error window over the active window or main screen.
  private func center(window: NSWindow, size: CGSize) {
    if let parentWindow = NSApp.keyWindow ?? NSApp.mainWindow {
      let parentFrame = parentWindow.frame
      window.setFrameOrigin(
        NSPoint(
          x: parentFrame.midX - size.width / 2,
          y: parentFrame.midY - size.height / 2
        )
      )
      return
    }

    if let screenFrame = NSScreen.main?.visibleFrame {
      window.setFrameOrigin(
        NSPoint(
          x: screenFrame.midX - size.width / 2,
          y: screenFrame.midY - size.height / 2
        )
      )
    }
  }

  /// Resets controller state when the user closes the window directly.
  func windowWillClose(_ notification: Notification) {
    window = nil
    hostingController = NSHostingController(rootView: AnyView(EmptyView()))
  }

  /// Builds one shared presentation model from the app-specific failure state.
  private func makePresentation(
    failureState: Config.LoadFailureState,
    configPath: String
  ) -> SharedConfigErrorPresentation {
    let configError = failureState.error as? ConfigError

    return SharedConfigErrorPresentation(
      windowTitle: "EasyBar Config Error",
      title: title(for: failureState.context),
      summary: summary(for: failureState.context),
      filePath: configPath,
      locationText: configError?.configPath,
      problemItemText: configError?.problemItem,
      problemValueText: configError?.problemValue,
      detailText: detailText(for: failureState.error, configError: configError),
      openButtonTitle: "Open Config",
      retryButtonTitle: "Reload Config"
    )
  }

  /// Builds one shared presentation model for non-fatal config warnings.
  private func makeWarningPresentation(
    warnings: [String],
    configPath: String
  ) -> SharedConfigErrorPresentation {
    let detailText: String
    if warnings.count == 1 {
      detailText = warnings[0]
    } else {
      detailText = warnings.enumerated().map { index, warning in
        "\(index + 1). \(warning)"
      }.joined(separator: " ")
    }

    return SharedConfigErrorPresentation(
      windowTitle: "EasyBar Config Warning",
      title: warnings.count == 1
        ? "EasyBar loaded the config with a warning"
        : "EasyBar loaded the config with warnings",
      summary: warnings.count == 1
        ? "The config is valid and active, but one setting needs attention."
        : "The config is valid and active, but multiple settings need attention.",
      filePath: configPath,
      locationSectionTitle: nil,
      problemSectionTitle: nil,
      detailSectionTitle: warnings.count == 1 ? "Warning" : "Warnings",
      detailText: detailText,
      openButtonTitle: "Open Config",
      retryButtonTitle: "Reload Config"
    )
  }

  /// Returns the headline text for the failure context.
  private func title(for context: Config.LoadFailureContext) -> String {
    switch context {
    case .initialLoad:
      return "EasyBar started with a config problem"
    case .reloadKeptPreviousConfig:
      return "EasyBar could not apply the new config"
    }
  }

  /// Returns the fallback summary for the failure context.
  private func summary(for context: Config.LoadFailureContext) -> String {
    switch context {
    case .initialLoad:
      return "The bar is running with fallback defaults until the config is fixed and reloaded."
    case .reloadKeptPreviousConfig:
      return
        "The previous working config is still active. Fix the file and reload config to apply the changes."
    }
  }

  /// Returns the best available user-facing detail text.
  private func detailText(
    for error: any Error,
    configError: ConfigError?
  ) -> String {
    if let configError {
      return configError.detail
    }

    return error.localizedDescription
  }
}
