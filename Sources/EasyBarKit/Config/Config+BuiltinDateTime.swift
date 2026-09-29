import Foundation

extension Config {

  /// Shared configuration for one standalone formatted date or time widget.
  struct FormattedBuiltinConfig: @unchecked Sendable {
    /// Stores content data.
    struct Content {
      /// The format for this content.
      var format: String
    }

    /// The placement for this formatted builtin config.
    var placement: BuiltinWidgetPlacement
    /// The style for this formatted builtin config.
    var style: BuiltinWidgetStyle
    /// The content for this formatted builtin config.
    var content: Content

    /// The time default for this formatted builtin config.
    static let timeDefault = FormattedBuiltinConfig(
      placement: .init(enabled: false, position: .right, order: 40),
      style: .init(
        icon: "􀐫",
        textColorHex: "#ffffff",
        backgroundColorHex: "#1a1a1a",
        borderColorHex: "#333333",
        borderWidth: 1,
        cornerRadius: 8,
        marginX: 0,
        marginY: 0,
        paddingX: 8,
        paddingY: 4,
        spacing: 6,
        opacity: 1
      ),
      content: .init(format: "HH:mm")
    )

    /// The date default for this formatted builtin config.
    static let dateDefault = FormattedBuiltinConfig(
      placement: .init(enabled: false, position: .right, order: 50),
      style: .init(
        icon: "􀉉",
        textColorHex: "#ffffff",
        backgroundColorHex: "#1a1a1a",
        borderColorHex: "#333333",
        borderWidth: 1,
        cornerRadius: 8,
        marginX: 0,
        marginY: 0,
        paddingX: 8,
        paddingY: 4,
        spacing: 6,
        opacity: 1
      ),
      content: .init(format: "yyyy-MM-dd")
    )
  }

  /// Parses time builtin.
  func parseTimeBuiltin(from builtins: ConfigReader) throws {
    guard let reader = try builtins.optionalSection("time") else { return }
    builtinTime = try parseFormattedBuiltin(reader: reader, fallback: builtinTime)
  }

  /// Parses date builtin.
  func parseDateBuiltin(from builtins: ConfigReader) throws {
    guard let reader = try builtins.optionalSection("date") else { return }
    builtinDate = try parseFormattedBuiltin(reader: reader, fallback: builtinDate)
  }

  /// Parses formatted builtin.
  private func parseFormattedBuiltin(
    reader: ConfigReader,
    fallback: FormattedBuiltinConfig
  ) throws -> FormattedBuiltinConfig {
    FormattedBuiltinConfig(
      placement: try parseBuiltinPlacement(reader: reader, fallback: fallback.placement),
      style: try parseBuiltinStyle(
        reader: try reader.section("style"), fallback: fallback.style),
      content: .init(
        format: try reader.section("content").string("format", fallback: fallback.content.format)
      )
    )
  }
}
