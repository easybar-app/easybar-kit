/// User-facing config schema metadata used by generators and typo warnings.
///
/// Keep this close to the parsed config types so default config examples,
/// configuration reference docs, and unknown-key warnings share one source.
public enum ConfigSchemaRegistry {}

extension ConfigSchemaRegistry {
  /// One line in the generated default config file.
  public enum Line: Sendable {
    case blank
    case comment(String)
    case section(name: String, commented: Bool, prefix: String, documented: Bool)
    case entry(
      key: String,
      value: String,
      description: String,
      commented: Bool,
      prefix: String,
      documented: Bool
    )
    case optionalEntry(key: String, value: String, description: String)
  }

  /// Returns the section.
  static func section(
    name: String,
    commented: Bool = false,
    prefix: String = "",
    documented: Bool = true
  ) -> Line {
    .section(
      name: name,
      commented: commented,
      prefix: prefix,
      documented: documented
    )
  }

  /// Returns the entry.
  static func entry(
    key: String,
    value: String,
    description: String,
    commented: Bool = false,
    prefix: String = "",
    documented: Bool = true
  ) -> Line {
    .entry(
      key: key,
      value: value,
      description: description,
      commented: commented,
      prefix: prefix,
      documented: documented
    )
  }

  /// Returns the optional entry.
  static func optionalEntry(
    key: String,
    value: String,
    description: String
  ) -> Line {
    .optionalEntry(
      key: key,
      value: value,
      description: description
    )
  }

  /// Returns the common style section shared by ordinary built-in widgets.
  static func widgetStyleLines(
    sectionName: String,
    icon: String,
    iconDescription: String = "Leading icon of the widget.",
    textDescription: String = "Text color of the widget.",
    background: String = "\"theme.surface\"",
    border: String = "\"theme.border\"",
    borderWidth: String = "1",
    cornerRadius: String = "8",
    paddingX: String = "8",
    paddingY: String = "4",
    spacing: String = "6",
    spacingDescription: String = "Gap between the icon and text.",
    opacity: String = "1.0"
  ) -> [Line] {
    [
      section(name: sectionName),
      entry(key: "icon", value: icon, description: iconDescription),
      entry(key: "text_color", value: "\"theme.text\"", description: textDescription),
      entry(
        key: "background_color",
        value: background,
        description: "Background color of the widget."
      ),
      entry(key: "border_color", value: border, description: "Border color of the widget."),
      entry(key: "border_width", value: borderWidth, description: "Border width of the widget."),
      entry(
        key: "corner_radius",
        value: cornerRadius,
        description: "Corner radius of the widget background."
      ),
      entry(key: "margin_x", value: "0", description: "Horizontal outer margin around the widget."),
      entry(key: "margin_y", value: "0", description: "Vertical outer margin around the widget."),
      entry(key: "padding_x", value: paddingX, description: "Horizontal inner padding of the widget."),
      entry(key: "padding_y", value: paddingY, description: "Vertical inner padding of the widget."),
      entry(key: "spacing", value: spacing, description: spacingDescription),
      entry(key: "opacity", value: opacity, description: "Overall opacity of the widget."),
    ]
  }
}
