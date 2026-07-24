extension ConfigSchemaRegistry {
  static let privacySpacerLines: [Line] = [
    section(name: "builtins.privacy_spacer"),
    entry(
      key: "enabled",
      value: "true",
      description: "Shows or hides the predefined privacy spacer."
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
      value: "12",
      description: "Width of the invisible reserved area in points (1–100)."
    ),
    .blank,
    .comment("# Additional named spacers are config-only and may use any section name."),
    section(
      name: "builtins.spacers.example",
      commented: true,
      prefix: "#",
      documented: true
    ),
    entry(
      key: "enabled",
      value: "true",
      description: "Shows or hides this named spacer.",
      commented: true,
      prefix: "#"
    ),
    entry(
      key: "position",
      value: "\"right\"",
      description: "Places this spacer on the left, center, or right side of the bar.",
      commented: true,
      prefix: "#"
    ),
    entry(
      key: "order",
      value: "1000",
      description: "Sort order among widgets in the same position.",
      commented: true,
      prefix: "#"
    ),
    entry(
      key: "group",
      value: "\"system\"",
      description: "Optional native group id that should contain this spacer.",
      commented: true,
      prefix: "# "
    ),
    entry(
      key: "width",
      value: "8",
      description: "Width of the invisible reserved area in points (1–100).",
      commented: true,
      prefix: "#"
    ),
    .blank,
  ]
}
