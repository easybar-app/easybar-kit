import Foundation

extension Config {

  /// Built-in CPU widget config.
  struct CPUBuiltinConfig: @unchecked Sendable {
    /// CPU graph content settings.
    struct Content {
      /// The label for this content.
      var label: String
      /// The history size for this content.
      var historySize: Int
      /// The line width for this content.
      var lineWidth: Double
      /// The color hex for this content.
      var colorHex: String?
      /// The sample interval seconds for this content.
      var sampleIntervalSeconds: Double
    }

    /// Shared placement settings.
    var placement: BuiltinWidgetPlacement
    /// Shared visual style settings.
    var style: BuiltinWidgetStyle
    /// CPU-specific content settings.
    var content: Content

    /// Whether this CPU builtin config is enabled.
    var enabled: Bool {
      get { placement.enabled }
      set { placement.enabled = newValue }
    }

    /// The position for this CPU builtin config.
    var position: WidgetPosition {
      get { placement.position }
      set { placement.position = newValue }
    }

    /// The order for this CPU builtin config.
    var order: Int {
      get { placement.order }
      set { placement.order = newValue }
    }

    /// The label for this CPU builtin config.
    var label: String {
      get { content.label }
      set { content.label = newValue }
    }

    /// The history size for this CPU builtin config.
    var historySize: Int {
      get { content.historySize }
      set { content.historySize = newValue }
    }

    /// The line width for this CPU builtin config.
    var lineWidth: Double {
      get { content.lineWidth }
      set { content.lineWidth = newValue }
    }

    /// The color hex for this CPU builtin config.
    var colorHex: String? {
      get { content.colorHex }
      set { content.colorHex = newValue }
    }

    /// The sample interval seconds for this CPU builtin config.
    var sampleIntervalSeconds: Double {
      get { content.sampleIntervalSeconds }
      set { content.sampleIntervalSeconds = newValue }
    }

    /// Default CPU widget config.
    static let `default` = CPUBuiltinConfig(
      placement: .init(
        enabled: false,
        position: .right,
        order: 10
      ),
      style: .init(
        icon: "󰍛",
        textColorHex: "",
        backgroundColorHex: "",
        borderColorHex: "",
        borderWidth: 0,
        cornerRadius: 0,
        marginX: 0,
        marginY: 0,
        paddingX: 8,
        paddingY: 4,
        spacing: 6,
        opacity: 1
      ),
      content: .init(
        label: "CPU",
        historySize: 10,
        lineWidth: 1.8,
        colorHex: "#a6da95",
        sampleIntervalSeconds: 1
      )
    )
  }

  /// Parses the built-in CPU widget.
  func parseCPUBuiltin(from builtins: ConfigReader) throws {
    guard let cpu = try builtins.optionalSection("cpu") else { return }

    let placement = try parseBuiltinPlacement(
      reader: cpu,
      fallback: builtinCPU.placement
    )

    let style = try parseBuiltinStyle(
      reader: try cpu.section("style"),
      fallback: builtinCPU.style
    )

    let content = try parseCPUContent(
      reader: try cpu.section("content"),
      fallback: builtinCPU.content
    )

    builtinCPU = CPUBuiltinConfig(
      placement: placement,
      style: style,
      content: content
    )
  }

  /// Parses the CPU content block.
  private func parseCPUContent(
    reader: ConfigReader,
    fallback: CPUBuiltinConfig.Content
  ) throws -> CPUBuiltinConfig.Content {
    CPUBuiltinConfig.Content(
      label: try reader.string("label", fallback: fallback.label),
      historySize: try reader.int("history_size", fallback: fallback.historySize, minimum: 2),
      lineWidth: try reader.double(
        "line_width",
        fallback: fallback.lineWidth,
        minimum: 0
      ),
      colorHex: try reader.optionalColor("color", fallback: fallback.colorHex),
      sampleIntervalSeconds: try reader.double(
        "sample_interval_seconds",
        fallback: fallback.sampleIntervalSeconds,
        minimum: 1
      )
    )
  }
}
