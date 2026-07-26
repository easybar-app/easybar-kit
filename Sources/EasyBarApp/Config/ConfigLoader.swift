import EasyBarShared
import Foundation
import SwiftTOMLEdit

extension Config {

  func load(validateOnly: Bool = false) throws {
    resetRegisteredDirectories()
    configWarnings = []

    let resolvedConfigPath = configPath
    let fileURL = URL(fileURLWithPath: resolvedConfigPath)

    let loadedConfig = try loadConfigFile(from: fileURL, resolvedPath: resolvedConfigPath)
    try parseConfig(from: loadedConfig.table)
    configWarnings =
      ConfigUnknownKeyWarningBuilder.warnings(for: loadedConfig.table)
      + ConfigSemanticWarningBuilder.warnings(for: snapshot())

    if !validateOnly {
      try ensureRequiredDirectoriesExist()
    }
  }

  func environmentConfigPathOverride() -> String? {
    return expandedEnvironmentPath(named: SharedEnvironmentKeys.configPath)
  }

  func environmentLogLevelOverride() throws -> ProcessLogLevel? {
    guard let value = stringEnvironmentValue(named: SharedEnvironmentKeys.loggingLevel) else {
      return nil
    }

    return try parseLogLevel(
      value,
      path: "environment.\(SharedEnvironmentKeys.loggingLevel)"
    )
  }

  private func loadConfigFile(
    from fileURL: URL,
    resolvedPath: String
  ) throws -> (table: TOMLTable, text: String?) {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      return (TOMLTable(), nil)
    }

    let data: Data

    do {
      data = try Data(contentsOf: fileURL)
    } catch {
      throw ConfigError.invalidValue(
        path: "config file",
        message: "failed to read file at \(resolvedPath): \(error.localizedDescription)"
      )
    }

    guard let text = String(data: data, encoding: .utf8) else {
      throw ConfigError.invalidValue(
        path: "config file",
        message: "file is not valid UTF-8"
      )
    }

    do {
      return (try TOMLTable(string: text), text)
    } catch let error as TOMLParseError {
      throw makeParseFailure(from: error, text: text)
    } catch {
      throw ConfigError.invalidValue(
        path: "config",
        message: "parse failed: \(error)"
      )
    }
  }

  private func parseConfig(from toml: TOMLTable) throws {
    do {
      try parseApp(from: toml)
      try parseLogging(from: toml)
      try parseAgents(from: toml)
      try parseTheme(from: toml)
      applyThemeDefaults()
      try parseBar(from: toml)
      try parseBuiltins(from: toml)
    } catch let error as ConfigError {
      throw error
    } catch {
      throw ConfigError.invalidValue(
        path: "config",
        message: "parse failed: \(error)"
      )
    }
  }
}
