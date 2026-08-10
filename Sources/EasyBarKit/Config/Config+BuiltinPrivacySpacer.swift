import Foundation

extension Config {
  /// Native invisible spacer configuration shared by the predefined and named spacers.
  struct SpacerBuiltinConfig: @unchecked Sendable {
    /// Shared placement settings.
    var placement: BuiltinWidgetPlacement
    /// Reserved width in points.
    var width: Double

    var enabled: Bool {
      get { placement.enabled }
      set { placement.enabled = newValue }
    }

    var position: WidgetPosition {
      get { placement.position }
      set { placement.position = newValue }
    }

    var order: Int {
      get { placement.order }
      set { placement.order = newValue }
    }

    /// Default configuration for the predefined privacy spacer.
    static let privacyDefault = SpacerBuiltinConfig(
      placement: .init(
        enabled: true,
        position: .right,
        order: 1_000
      ),
      width: 12
    )

    /// Default configuration for an explicitly declared named spacer.
    static let namedDefault = SpacerBuiltinConfig(
      placement: .init(
        enabled: true,
        position: .right,
        order: 1_000
      ),
      width: 8
    )
  }

  /// One config-only named spacer declared below `builtins.spacers`.
  struct NamedSpacerBuiltinConfig: @unchecked Sendable {
    /// User-defined section name.
    var id: String
    /// Shared native spacer configuration.
    var config: SpacerBuiltinConfig
  }

  /// Parses the predefined privacy spacer.
  func parsePrivacySpacerBuiltin(from builtins: ConfigReader) throws {
    guard let spacer = try builtins.optionalSection("privacy_spacer") else { return }

    builtinPrivacySpacer = try parseSpacerBuiltin(
      from: spacer,
      fallback: builtinPrivacySpacer
    )
  }

  /// Parses arbitrary config-only spacers from `builtins.spacers.<name>` sections.
  func parseSpacerBuiltins(from builtins: ConfigReader) throws {
    guard let spacers = try builtins.optionalSection("spacers") else {
      builtinSpacers = []
      return
    }

    var parsed: [NamedSpacerBuiltinConfig] = []
    for id in spacers.keys {
      guard let spacer = try spacers.optionalSection(id) else { continue }
      parsed.append(
        NamedSpacerBuiltinConfig(
          id: id,
          config: try parseSpacerBuiltin(
            from: spacer,
            fallback: .namedDefault
          )
        )
      )
    }

    builtinSpacers = parsed.sorted { $0.id < $1.id }
  }

  /// Parses the settings shared by all native spacers.
  private func parseSpacerBuiltin(
    from spacer: ConfigReader,
    fallback: SpacerBuiltinConfig
  ) throws -> SpacerBuiltinConfig {
    SpacerBuiltinConfig(
      placement: try parseBuiltinPlacement(
        reader: spacer,
        fallback: fallback.placement
      ),
      width: try spacer.double(
        "width",
        fallback: fallback.width,
        minimum: 1,
        maximum: 100
      )
    )
  }
}
