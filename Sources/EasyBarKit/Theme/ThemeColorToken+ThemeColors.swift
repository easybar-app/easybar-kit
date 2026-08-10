extension ThemeColorToken {
  nonisolated(unsafe) fileprivate static let themeColorKeyPaths:
    [ThemeColorToken: WritableKeyPath<Config.ThemeColors, String>] = [
      .background: \.background,
      .surface: \.surface,
      .surfaceElevated: \.surfaceElevated,
      .surfaceHover: \.surfaceHover,
      .text: \.text,
      .textSecondary: \.textSecondary,
      .textTertiary: \.textTertiary,
      .muted: \.muted,
      .mutedSecondary: \.mutedSecondary,
      .outsideMonth: \.outsideMonth,
      .accent: \.accent,
      .accentSecondary: \.accentSecondary,
      .accentSoft: \.accentSoft,
      .success: \.success,
      .successSecondary: \.successSecondary,
      .warning: \.warning,
      .orange: \.orange,
      .error: \.error,
      .danger: \.danger,
      .border: \.border,
      .borderStrong: \.borderStrong,
      .borderSubtle: \.borderSubtle,
      .selectionText: \.selectionText,
      .selectionBackground: \.selectionBackground,
      .transparent: \.transparent,
      .overlayOutline: \.overlayOutline,
      .overlayText: \.overlayText,
    ]

  fileprivate var themeColorKeyPath: WritableKeyPath<Config.ThemeColors, String> {
    guard let keyPath = Self.themeColorKeyPaths[self] else {
      preconditionFailure("missing theme color key path for \(rawValue)")
    }

    return keyPath
  }
}

extension Config.ThemeColors {
  private static let empty = Self(
    background: "",
    surface: "",
    surfaceElevated: "",
    surfaceHover: "",
    text: "",
    textSecondary: "",
    textTertiary: "",
    muted: "",
    mutedSecondary: "",
    outsideMonth: "",
    accent: "",
    accentSecondary: "",
    accentSoft: "",
    success: "",
    successSecondary: "",
    warning: "",
    orange: "",
    error: "",
    danger: "",
    border: "",
    borderStrong: "",
    borderSubtle: "",
    selectionText: "",
    selectionBackground: "",
    transparent: "",
    overlayOutline: "",
    overlayText: ""
  )

  /// Creates one theme color set from values keyed by token.
  init(valuesByToken values: [ThemeColorToken: String]) {
    self = Self.empty

    for token in ThemeColorToken.allCases {
      self[keyPath: token.themeColorKeyPath] = values[token] ?? ""
    }
  }

  /// Returns one color value for the given token.
  subscript(token: ThemeColorToken) -> String {
    get {
      self[keyPath: token.themeColorKeyPath]
    }
    set {
      self[keyPath: token.themeColorKeyPath] = newValue
    }
  }

  /// Returns all colors keyed by their public token names.
  var valuesByName: [String: String] {
    Dictionary(
      uniqueKeysWithValues: ThemeColorToken.allCases.map { token in
        (token.rawValue, self[token])
      }
    )
  }
}
