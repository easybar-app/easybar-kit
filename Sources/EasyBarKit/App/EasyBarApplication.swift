import AppKit
import Darwin
import EasyBarShared
import Foundation

/// Product identity used by one EasyBarKit frontend.
public struct EasyBarApplicationIdentity: Sendable {
  public let displayName: String
  public let processName: String
  public let loggerLabel: String
  public let logFileName: String
  public let defaultConfigRelativePath: String?
  public let defaultRuntimeRelativePath: String?
  public let defaultEnvironment: [String: String]
  /// Host-owned built-in surfaces enabled for this frontend.
  public let builtInSurfacePolicy: EasyBarBuiltInSurfacePolicy

  public init(
    displayName: String,
    processName: String,
    loggerLabel: String,
    logFileName: String,
    defaultConfigRelativePath: String? = nil,
    defaultRuntimeRelativePath: String? = nil,
    defaultEnvironment: [String: String] = [:],
    builtInSurfacePolicy: EasyBarBuiltInSurfacePolicy = .all
  ) {
    self.displayName = displayName
    self.processName = processName
    self.loggerLabel = loggerLabel
    self.logFileName = logFileName
    self.defaultConfigRelativePath = defaultConfigRelativePath
    self.defaultRuntimeRelativePath = defaultRuntimeRelativePath
    self.defaultEnvironment = defaultEnvironment
    self.builtInSurfacePolicy = builtInSurfacePolicy
  }

  /// Applies frontend bootstrap defaults without overriding explicit user values.
  fileprivate func applyBootstrapEnvironment() {
    let environment = ProcessInfo.processInfo.environment

    if environment[SharedEnvironmentKeys.configPath] == nil,
      let defaultConfigRelativePath
    {
      setenv(
        SharedEnvironmentKeys.configPath,
        SharedPathDefaults.homeRelativePath(defaultConfigRelativePath).path,
        0
      )
    }

    if environment[SharedEnvironmentKeys.runtimeDirectory] == nil,
      let defaultRuntimeRelativePath
    {
      setenv(
        SharedEnvironmentKeys.runtimeDirectory,
        SharedPathDefaults.homeRelativePath(defaultRuntimeRelativePath).path,
        0
      )
    }

    for (key, value) in defaultEnvironment where environment[key] == nil {
      setenv(key, value, 0)
    }
  }
}

/// Shared AppKit launcher used by EasyBar frontends.
public enum EasyBarApplication {
  /// Starts the shared runtime and asks the supplied factory to present it.
  @MainActor
  public static func run(
    identity: EasyBarApplicationIdentity,
    surfaceFactory: @escaping EasyBarSurfaceFactory
  ) {
    if CommandLine.arguments.dropFirst() == ["--version"] {
      print("\(identity.displayName) \(BuildInfo.appVersion)")
      return
    }

    identity.applyBootstrapEnvironment()

    let logger = ProcessLogger(label: identity.loggerLabel)
    logger.debug("main entered", .field("pid", getpid()))

    let app = NSApplication.shared
    let delegate = AppDelegate(
      logger: logger,
      identity: identity,
      surfaceFactory: surfaceFactory
    )
    app.delegate = delegate

    logger.debug("NSApplication.run starting")
    app.run()
    logger.debug("NSApplication.run ended", .field("exit_code", delegate.exitCode))

    delegate.stop()
    Foundation.exit(delegate.exitCode)
  }
}
