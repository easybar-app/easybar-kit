import Cocoa

@MainActor
/// Coordinates app delegate state and behavior.
final class AppDelegate: NSObject, NSApplicationDelegate {
  private lazy var appController = AppController { [weak self] in
    self?.stopApplication(exitCode: 75)
  }

  /// Exit code returned by `EasyBarCalendarAgentMain.main()` after the app loop stops.
  private(set) var exitCode: Int32 = 0

  /// Starts the calendar agent after launch.
  func applicationDidFinishLaunching(_ notification: Notification) {
    guard let terminationExitCode = appController.start().terminationExitCode else { return }
    stopApplication(exitCode: terminationExitCode)
  }

  /// Stops the calendar agent before termination.
  func applicationWillTerminate(_ notification: Notification) {
    stop()
  }

  /// Stops the calendar agent explicitly from `main()` after the app loop returns.
  func stop() {
    appController.stop()
  }

  /// Stops AppKit without forcing a successful process exit so `main()` can return the chosen code.
  private func stopApplication(exitCode: Int32) {
    self.exitCode = exitCode
    NSApp.stop(nil)
    if let wakeEvent = NSEvent.otherEvent(
      with: .applicationDefined,
      location: .zero,
      modifierFlags: [],
      timestamp: 0,
      windowNumber: 0,
      context: nil,
      subtype: 0,
      data1: 0,
      data2: 0
    ) {
      NSApp.postEvent(wakeEvent, atStart: true)
    }
  }
}
