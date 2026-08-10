import EasyBarShared
import Foundation

extension Config {
  /// Returns environment values required by the Lua runtime.
  func luaThemeEnvironment() -> [String: String] {
    return snapshot().luaThemeEnvironment()
  }
}

extension ConfigSnapshot {
  /// Returns environment values required by the Lua runtime.
  func luaThemeEnvironment() -> [String: String] {
    var environment = [
      SharedEnvironmentKeys.luaLoggingDirectory: logging.directory
    ]

    guard let value = luaThemeJSONString() else {
      return environment
    }

    environment[SharedEnvironmentKeys.luaThemeJSON] = value
    return environment
  }

  /// Encodes the resolved active theme for Lua widgets.
  private func luaThemeJSONString() -> String? {
    let payload: [String: Any] = [
      "name": theme.name,
      "colors": theme.colors.valuesByName,
    ]

    guard JSONSerialization.isValidJSONObject(payload) else {
      return nil
    }

    guard
      let data = try? JSONSerialization.data(
        withJSONObject: payload,
        options: [.sortedKeys]
      )
    else {
      return nil
    }

    return String(data: data, encoding: .utf8)
  }
}
