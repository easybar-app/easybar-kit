import Foundation

extension Config {

  /// Built-in CPU widget config.
  struct CPUBuiltinConfig: @unchecked Sendable {
    /// CPU graph content settings.
    struct Content {
      var label: String
      var historySize: Int
      var lineWidth: Double
      var colorHex: String?
      var sampleIntervalSeconds: Double
    }

    /// Shared placement settings.
    var placement: BuiltinWidgetPlacement
    /// Shared visual style settings.
    var style: BuiltinWidgetStyle
    /// CPU-specific content settings.
    var content: Content

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

    var label: String {
      get { content.label }
      set { content.label = newValue }
    }

    var historySize: Int {
      get { content.historySize }
      set { content.historySize = newValue }
    }

    var lineWidth: Double {
      get { content.lineWidth }
      set { content.lineWidth = newValue }
    }

    var colorHex: String? {
      get { content.colorHex }
      set { content.colorHex = newValue }
    }

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
