extension ConfigSchemaRegistry {
  /// Default config file lines in stable user-facing order.
  public static let lines: [Line] =
    coreLines
    + workspaceLines
    + systemLines
    + privacySpacerLines
    + calendarLines
    + clockLines

  private static let freeFormSections: Set<String> = [
    "app.env",
    "theme.colors",
    "builtins.calendar.composer.alert_labels",
    "builtins.calendar.composer.travel_time_labels",
  ]

  private static let placementKeys: Set<String> = [
    "enabled", "position", "order", "group",
  ]

  private static let widgetStyleKeys: Set<String> = [
    "icon", "text_color", "background_color", "border_color", "border_width",
    "corner_radius", "margin_x", "margin_y", "padding_x", "padding_y", "spacing",
    "opacity",
  ]

  private static let knownKeysBySection: [String: Set<String>] = {
    var sections: [String: [String]] = [:]

    func addSection(_ path: String) {
      if sections[path] == nil {
        sections[path] = []
      }

      guard !path.isEmpty else { return }
      let parts = path.split(separator: ".").map(String.init)
      guard !parts.isEmpty else { return }

      addKey(section: "", key: parts[0])

      if parts.count > 1 {
        for index in 1..<parts.count {
          let parent = parts[..<index].joined(separator: ".")
          addKey(section: parent, key: parts[index])
        }
      }
    }

    func addKey(section: String, key: String) {
      if sections[section] == nil {
        sections[section] = []
      }

      if sections[section]?.contains(key) == false {
        sections[section]?.append(key)
      }
    }

    var currentSection = ""
    addSection(currentSection)

    for line in lines {
      switch line {
      case .section(let name, _, _, _):
        currentSection = name
        addSection(name)
      case .entry(let key, _, _, _, _, _), .optionalEntry(let key, _, _):
        addKey(section: currentSection, key: key)
      case .blank, .comment:
        continue
      }
    }

    addSection("theme.colors")
    addKey(section: "theme", key: "colors")

    return sections.mapValues(Set.init)
  }()

  /// Returns true when a section accepts arbitrary keys.
  public static func isFreeFormSection(_ path: String) -> Bool {
    freeFormSections.contains(path)
  }

  /// Returns known keys for one TOML section path.
  public static func knownKeys(for path: String) -> Set<String> {
    if isBuiltinGroup(path) {
      return placementKeys.union(["style"])
    }

    if isBuiltinGroupStyle(path) {
      return widgetStyleKeys
    }

    if isNamedBuiltinSpacer(path) {
      return placementKeys.union(["width"])
    }

    return knownKeysBySection[path] ?? []
  }

  /// Returns true when a TOML section path is known.
  public static func isKnownSection(_ path: String) -> Bool {
    knownKeysBySection[path] != nil
      || freeFormSections.contains(path)
      || isBuiltinGroup(path)
      || isBuiltinGroupStyle(path)
      || isNamedBuiltinSpacer(path)
  }

  private static func isBuiltinGroup(_ path: String) -> Bool {
    let components = path.split(separator: ".")
    return components.count == 3
      && components[0] == "builtins"
      && components[1] == "groups"
  }

  private static func isBuiltinGroupStyle(_ path: String) -> Bool {
    let components = path.split(separator: ".")
    return components.count == 4
      && components[0] == "builtins"
      && components[1] == "groups"
      && components[3] == "style"
  }

  private static func isNamedBuiltinSpacer(_ path: String) -> Bool {
    let components = path.split(separator: ".")
    return components.count == 3
      && components[0] == "builtins"
      && components[1] == "spacers"
  }
}
