import Foundation

extension Config {
  /// Built-in invisible spacer used to reserve room at a bar edge.
  struct PrivacySpacerBuiltinConfig: @unchecked Sendable {
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

    /// Default privacy-spacer configuration.
    static let `default` = PrivacySpacerBuiltinConfig(
      placement: .init(
        enabled: false,
        position: .right,
        order: 1_000
      ),
      width: 22
    )
  }

  /// Parses the built-in privacy spacer.
  func parsePrivacySpacerBuiltin(from builtins: ConfigReader) throws {
    guard let spacer = try builtins.optionalSection("privacy_spacer") else { return }

    builtinPrivacySpacer = PrivacySpacerBuiltinConfig(
      placement: try parseBuiltinPlacement(
        reader: spacer,
        fallback: builtinPrivacySpacer.placement
      ),
      width: try spacer.double(
        "width",
        fallback: builtinPrivacySpacer.width,
        minimum: 1,
        maximum: 100
      )
    )
  }
}
