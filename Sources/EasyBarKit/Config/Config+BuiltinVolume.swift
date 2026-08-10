import Foundation

extension Config {

  /// Built-in volume widget config.
  struct VolumeBuiltinConfig: @unchecked Sendable {
    /// Volume display content settings.
    struct Content {
      var mutedIcon: String
      var lowIcon: String
      var highIcon: String
      var showPercentage: Bool
      var minValue: Double
      var maxValue: Double
      var step: Double
    }

    /// Volume slider behavior settings.
    struct Slider {
      var expandToSliderOnHover: Bool
      var width: Double
    }

    /// Shared placement settings.
    var placement: BuiltinWidgetPlacement
    /// Text and visual chrome settings.
    var style: BuiltinWidgetTextStyle
    /// Volume-specific content settings.
    var content: Content
    /// Slider behavior settings.
    var slider: Slider

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

    var mutedIcon: String {
      get { content.mutedIcon }
      set { content.mutedIcon = newValue }
    }

    var lowIcon: String {
      get { content.lowIcon }
      set { content.lowIcon = newValue }
    }

    var highIcon: String {
      get { content.highIcon }
      set { content.highIcon = newValue }
    }

    var showPercentage: Bool {
      get { content.showPercentage }
      set { content.showPercentage = newValue }
    }

    var minValue: Double {
      get { content.minValue }
      set { content.minValue = newValue }
    }

    var maxValue: Double {
      get { content.maxValue }
      set { content.maxValue = newValue }
    }

    var step: Double {
      get { content.step }
      set { content.step = newValue }
    }

    var expandToSliderOnHover: Bool {
      get { slider.expandToSliderOnHover }
      set { slider.expandToSliderOnHover = newValue }
    }

    var sliderWidth: Double {
      get { slider.width }
      set { slider.width = newValue }
    }

    /// Default volume widget config.
    static let `default` = VolumeBuiltinConfig(
      placement: .init(
        enabled: false,
        position: .right,
        order: 20
      ),
      style: .init(
        textColorHex: "#cdd6f4",
        chrome: .init(
          backgroundColorHex: "#00000000",
          borderColorHex: "#00000000",
          borderWidth: 0,
          cornerRadius: 8,
          marginX: 0,
          marginY: 0,
          paddingX: 8,
          paddingY: 0,
          spacing: 8,
          opacity: 1
        )
      ),
      content: .init(
        mutedIcon: "􀊢",
        lowIcon: "􀊤",
        highIcon: "􀊦",
        showPercentage: true,
        minValue: 0,
        maxValue: 100,
        step: 1
      ),
      slider: .init(
        expandToSliderOnHover: true,
        width: 80
      )
    )
  }

  /// Parses the built-in volume widget.
  func parseVolumeBuiltin(from builtins: ConfigReader) throws {
    guard let volume = try builtins.optionalSection("volume") else { return }

    let placement = try parseBuiltinPlacement(
      reader: volume,
      fallback: builtinVolume.placement
    )

    let style = try parseBuiltinTextStyle(
      reader: try volume.section("style"),
      fallback: builtinVolume.style
    )

    let content = try parseVolumeContent(
      reader: try volume.section("content"),
      fallback: builtinVolume.content
    )

    let slider = try parseVolumeSlider(
      reader: try volume.section("slider"),
      fallback: builtinVolume.slider
    )

    try validateVolumeContent(content)
    try validateVolumeSlider(slider)

    builtinVolume = VolumeBuiltinConfig(
      placement: placement,
      style: style,
      content: content,
      slider: slider
    )
  }

  /// Parses the volume content block.
  private func parseVolumeContent(
    reader: ConfigReader,
    fallback: VolumeBuiltinConfig.Content
  ) throws -> VolumeBuiltinConfig.Content {
    let step = try reader.double(
      "step",
      fallback: fallback.step,
      minimum: 0,
      maximum: 100
    )
    guard step > 0 else {
      throw ConfigError.invalidValue(
        path: reader.path(for: "step"),
        message: "expected a value greater than 0 and less than or equal to 100"
      )
    }

    return VolumeBuiltinConfig.Content(
      mutedIcon: try reader.string("muted_icon", fallback: fallback.mutedIcon),
      lowIcon: try reader.string("low_icon", fallback: fallback.lowIcon),
      highIcon: try reader.string("high_icon", fallback: fallback.highIcon),
      showPercentage: try reader.bool("show_percentage", fallback: fallback.showPercentage),
      minValue: try reader.double(
        "min",
        fallback: fallback.minValue,
        minimum: 0,
        maximum: 100
      ),
      maxValue: try reader.double(
        "max",
        fallback: fallback.maxValue,
        minimum: 0,
        maximum: 100
      ),
      step: step
    )
  }

  /// Parses the volume slider block.
  private func parseVolumeSlider(
    reader: ConfigReader,
    fallback: VolumeBuiltinConfig.Slider
  ) throws -> VolumeBuiltinConfig.Slider {
    let width = try reader.double("width", fallback: fallback.width, minimum: 0)
    guard width > 0 else {
      throw ConfigError.invalidValue(
        path: reader.path(for: "width"),
        message: "expected a value greater than 0"
      )
    }

    return VolumeBuiltinConfig.Slider(
      expandToSliderOnHover: try reader.bool(
        "expand_to_slider_on_hover",
        fallback: fallback.expandToSliderOnHover
      ),
      width: width
    )
  }

  /// Validates volume range settings before they reach slider rendering.
  private func validateVolumeContent(_ content: VolumeBuiltinConfig.Content) throws {
    try validateFiniteNumber(content.minValue, path: "builtins.volume.content.min")
    try validateFiniteNumber(content.maxValue, path: "builtins.volume.content.max")
    try validateFiniteNumber(content.step, path: "builtins.volume.content.step")

    guard content.minValue < content.maxValue else {
      throw ConfigError.invalidValue(
        path: "builtins.volume.content.max",
        message: "expected a value greater than builtins.volume.content.min"
      )
    }

  }

  /// Validates volume slider layout settings.
  private func validateVolumeSlider(_ slider: VolumeBuiltinConfig.Slider) throws {
    try validateFiniteNumber(slider.width, path: "builtins.volume.slider.width")

  }

  /// Validates that one volume number is finite when loaded from config.
  private func validateFiniteNumber(_ value: Double, path: String) throws {
    guard value.isFinite else {
      throw ConfigError.invalidValue(
        path: path,
        message: "expected a finite number"
      )
    }
  }
}
