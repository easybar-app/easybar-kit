import AppKit
import EasyBarShared
import Foundation

/// AppKit delegate that forwards lifecycle events into `AppController`.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  /// Process logger used by the app shell.
  private let logger: ProcessLogger
  /// Product identity supplied by the frontend executable.
  private let identity: EasyBarApplicationIdentity
  /// Concrete surface factory supplied by the frontend executable.
  private let surfaceFactory: EasyBarSurfaceFactory

  /// Main app controller created after logger setup.
  private lazy var appController = AppController(
    logger: logger.child("app"),
    identity: identity,
    surfaceFactory: surfaceFactory
  ) { [weak self] in
    self?.requestTermination(exitCode: 0)
  }

  /// Exit code returned by `EasyBarAppMain.main()` after the app loop stops.
  private(set) var exitCode: Int32 = 0

  /// Whether graceful cleanup has already completed and AppKit may terminate.
  private var terminationCleanupCompleted = false

  /// Whether a graceful termination request is already running.
  private var terminationRequested = false

  /// Creates the app delegate with the process logger created by the entry point.
  init(
    logger: ProcessLogger,
    identity: EasyBarApplicationIdentity,
    surfaceFactory: @escaping EasyBarSurfaceFactory
  ) {
    self.logger = logger
    self.identity = identity
    self.surfaceFactory = surfaceFactory
    super.init()
  }

  /// Starts EasyBar after AppKit finishes launching.
  func applicationDidFinishLaunching(_ notification: Notification) {
    logger.debug("applicationDidFinishLaunching")

    guard appController.start() else {
      logger.error("AppController.start failed")
      exitCode = 1
      terminationCleanupCompleted = true
      NSApp.terminate(nil)
      return
    }

    logger.debug("AppController.start completed")
  }

  /// Requests graceful shutdown before allowing AppKit termination.
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard !terminationCleanupCompleted else {
      logger.debug("applicationShouldTerminate terminateNow")
      return .terminateNow
    }

    logger.debug("applicationShouldTerminate requesting graceful shutdown")
    requestTermination(exitCode: 0)
    return .terminateCancel
  }

  /// Stops EasyBar when AppKit is terminating.
  func applicationWillTerminate(_ notification: Notification) {
    stop()
  }

  /// Stops EasyBar explicitly from `main()` after the app loop returns.
  func stop() {
    appController.stop()
  }

  /// Starts graceful shutdown and then asks AppKit to terminate normally.
  private func requestTermination(exitCode: Int32) {
    guard !terminationCleanupCompleted else { return }
    guard !terminationRequested else { return }

    terminationRequested = true
    self.exitCode = exitCode

    appController.requestTermination { [weak self] in
      guard let self else { return }

      self.terminationCleanupCompleted = true
      NSApp.terminate(nil)
    }
  }
}
