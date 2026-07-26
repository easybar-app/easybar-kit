import Foundation
import SwiftTOMLEdit

/// Returns the resolved EasyBar config path, honoring EASYBAR_CONFIG_PATH.
func resolvedConfigPath() -> String {
  expandedEnvironmentPath(named: SharedEnvironmentKeys.configPath)
    ?? SharedPathDefaults.defaultConfigPath().path
}

/// Returns one parsed TOML table. Missing config files resolve to an empty table.
func parsedConfig(at path: String) throws -> TOMLTable {
  let url = URL(fileURLWithPath: path)

  guard FileManager.default.fileExists(atPath: url.path) else {
    return TOMLTable()
  }

  let data: Data
  do {
    data = try Data(contentsOf: url)
  } catch {
    throw SharedRuntimeConfigError.readFailure(
      path: path,
      message: error.localizedDescription
    )
  }

  guard let text = String(data: data, encoding: .utf8) else {
    throw SharedRuntimeConfigError.invalidValue(
      path: "config file",
      message: "file is not valid UTF-8"
    )
  }

  do {
    return try TOMLTable(string: text)
  } catch {
    throw SharedRuntimeConfigError.parseFailure(
      path: path,
      message: error.localizedDescription
    )
  }
}

typealias SharedRuntimeConfigReader = TOMLConfigReader<SharedRuntimeConfigError>

/// Returns a typed reader for the shared runtime config table.
func sharedRuntimeConfigReader(for table: TOMLTable) -> SharedRuntimeConfigReader {
  SharedRuntimeConfigReader(
    table: table,
    path: "",
    makeInvalidTypeError: SharedRuntimeConfigError.invalidType,
    makeInvalidValueError: SharedRuntimeConfigError.invalidValue
  )
}
