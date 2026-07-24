extension ConfigSchemaRegistry {
  static let privacySpacerLines: [Line] = [
    section(name: "builtins.privacy_spacer"),
    entry(
      key: "enabled",
      value: "false",
      description: "Shows or hides the privacy spacer."
    ),
    entry(
      key: "position",
      value: "\"right\"",
      description: "Places the spacer on the left, center, or right side of the bar."
    ),
    entry(
      key: "order",
      value: "1000",
      description: "Sort order among widgets in the same position."
    ),
    entry(
      key: "width",
      value: "22",
      description: "Width of the invisible reserved area in points (1–100)."
    ),
    .blank,
  ]
}
