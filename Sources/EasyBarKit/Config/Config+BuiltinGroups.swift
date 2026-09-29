import Foundation

extension Config {

  /// Native group container config used by built-in widgets.
  struct BuiltinGroupConfig {
    /// The stable identifier for this builtin group config.
    var id: String
    /// The placement for this builtin group config.
    var placement: BuiltinWidgetPlacement
    /// The style for this builtin group config.
    var style: BuiltinWidgetChromeStyle
  }

  /// Parses the built-in native groups.
  func parseBuiltinGroups(from builtins: ConfigReader) throws {
    guard let groups = try builtins.optionalSection("groups") else { return }

    var parsed: [BuiltinGroupConfig] = []

    for key in groups.keys {
      guard let group = try groups.optionalSection(key) else { continue }

      let placement = try parseBuiltinPlacement(
        reader: group,
        fallback: .init(
          enabled: true,
          position: .right,
          order: 40,
          group: nil
        ),
        allowGroupReference: false
      )

      let styleReader = try group.optionalSection("style") ?? group
      let style = try parseBuiltinChromeStyle(
        reader: styleReader,
        fallback: defaultBuiltinGroupStyle()
      )

      guard placement.enabled else { continue }

      parsed.append(
        BuiltinGroupConfig(
          id: key,
          placement: placement,
          style: style
        )
      )
    }

    builtinGroups = parsed
  }
}
