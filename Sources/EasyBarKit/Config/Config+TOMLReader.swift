import Foundation
import SwiftTOMLEdit

extension Config {
  /// App-local TOML reader that raises `ConfigError` diagnostics.
  typealias ConfigReader = TOMLConfigReader<ConfigError>

  /// Creates a reader for one app config table.
  func configReader(
    table: TOMLTable,
    path: String
  ) -> ConfigReader {
    ConfigReader(
      table: table,
      path: path,
      makeInvalidTypeError: { path, expected, actual in
        ConfigError.invalidType(path: path, expected: expected, actual: actual)
      },
      makeInvalidValueError: { path, message in
        ConfigError.invalidValue(path: path, message: message)
      }
    )
  }
}
