import AppKit
import EasyBarNetworkAgentCore
import EasyBarShared

/// App-level controller for the network agent process.
///
/// This type owns macOS application concerns such as logging setup, the
/// single-instance guard, activation policy changes, and authorization prompt
/// presentation. The reusable agent behavior lives in `NetworkAgentRuntime`.
@MainActor
final class AppController: NetworkAuthorizationPromptPresenter {
  private let logger = ProcessLogger(label: "easybar-network-agent")
  private let instanceGuard = SingleInstanceGuard()
  private let onRestartRequested: @MainActor () -> Void

  private var runtime: NetworkAgentRuntime?
  private var presentedAuthorizationPrompt = false

  /// Creates an app controller.
  init(onRestartRequested: @escaping @MainActor () -> Void) {
    self.onRestartRequested = onRestartRequested
  }

  /// Starts the network agent app shell and runtime.
  @discardableResult
  func start() -> AgentAppStartResult {
    guard
      let sharedConfig = AppShellSupport.prepareAgent(
        processName: "easybar-network-agent",
        logFileName: "network-agent.out",
        logger: logger,
        instanceGuard: instanceGuard
      )
    else {
      return .failed
    }

    let runtimeConfig = NetworkAgentRuntimeConfig.easyBar(
      runtimeConfig: sharedConfig,
      appVersion: BuildInfo.appVersion
    )

    guard runtimeConfig.isEnabled else {
      logger.info("network agent disabled in config")
      return .disabled
    }

    runtime = NetworkAgentRuntime(
      config: runtimeConfig,
      logger: logger.child("runtime"),
      promptPresenter: self,
      onRestartRequested: onRestartRequested
    )

    NSApp.setActivationPolicy(.accessory)

    guard runtime?.start() == true else {
      runtime = nil
      return .failed
    }

    return .running
  }

  /// Stops the network agent runtime.
  func stop() {
    runtime?.stop()
  }

  /// Prepares the app so the system location prompt can surface.
  func preparePrompt() {
    guard !presentedAuthorizationPrompt else { return }
    presentedAuthorizationPrompt = true

    let changed = NSApp.setActivationPolicy(.regular)
    logger.info(
      "network agent promoted for authorization prompt",
      .field("changed", changed)
    )
    NSApp.activate(ignoringOtherApps: true)
  }

  /// Restores accessory mode after authorization resolves.
  func restoreUI() {
    guard presentedAuthorizationPrompt else { return }
    presentedAuthorizationPrompt = false

    let changed = NSApp.setActivationPolicy(.accessory)
    logger.info(
      "network agent restored accessory mode",
      .field("changed", changed)
    )
  }

}
