import AppKit
import EasyBarCalendarCore
import EasyBarShared

/// App-level controller for the calendar agent process.
///
/// This type owns macOS application concerns such as logging setup, the
/// single-instance guard, activation policy, and runtime creation. The
/// long-running agent behavior lives in `CalendarAgentRuntime`.
@MainActor
final class AppController {
  private let logger = ProcessLogger(label: "easybar-calendar-agent")
  private let instanceGuard = SingleInstanceGuard()
  private let onRestartRequested: @MainActor () -> Void

  private var runtime: CalendarAgentRuntime?

  /// Creates an app controller.
  init(onRestartRequested: @escaping @MainActor () -> Void) {
    self.onRestartRequested = onRestartRequested
  }

  /// Starts the calendar agent app shell and runtime.
  @discardableResult
  func start() -> AgentAppStartResult {
    guard
      let sharedConfig = AppShellSupport.prepareAgent(
        processName: "easybar-calendar-agent",
        logFileName: "calendar-agent.out",
        logger: logger,
        instanceGuard: instanceGuard
      )
    else {
      return .failed
    }

    let runtimeConfig = CalendarAgentRuntimeConfig.easyBar(
      runtimeConfig: sharedConfig,
      appVersion: BuildInfo.appVersion
    )

    guard runtimeConfig.isEnabled else {
      logger.info("calendar agent disabled in config")
      return .disabled
    }

    runtime = CalendarAgentRuntime(
      config: runtimeConfig,
      logger: logger.child("runtime"),
      onRestartRequested: onRestartRequested
    )

    NSApp.setActivationPolicy(.accessory)

    guard runtime?.start() == true else {
      runtime = nil
      return .failed
    }

    return .running
  }

  /// Stops the calendar agent runtime.
  func stop() {
    runtime?.stop()
  }

}
