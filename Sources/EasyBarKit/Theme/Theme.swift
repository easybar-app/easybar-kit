import SwiftUI

/// Runtime theme helpers that resolve colors from immutable config snapshots.
enum Theme {

  /// Global icon font family used for Nerd Font / symbol-style icons.
  ///
  /// Change this in one place when you want to switch the app-wide icon font.
  private static let iconFontFamily = "Symbols Nerd Font Mono"

  /// Returns the bar background color from the active snapshot.
  static func barBackground(snapshot: ConfigSnapshot) -> Color {
    Color(hex: snapshot.bar.backgroundHex, snapshot: snapshot)
  }

  /// Returns the bar border color from the active snapshot.
  static func barBorder(snapshot: ConfigSnapshot) -> Color {
    Color(hex: snapshot.bar.borderHex, snapshot: snapshot)
  }

  /// Returns the fallback text color for views and nodes without a color.
  static func defaultTextColor(snapshot: ConfigSnapshot) -> Color {
    Color(hex: snapshot.theme.colors.text, snapshot: snapshot)
  }

  /// Returns the shared icon font used by popups and other icon-only text.
  static func iconFont(size: CGFloat) -> Font {
    return .custom(iconFontFamily, size: size)
  }

  /// Returns the border color for the focused app icon inside spaces.
  static func spaceFocusedAppBorder(snapshot: ConfigSnapshot) -> Color {
    Color(hex: snapshot.builtins.spaces.colors.focusedAppBorderHex, snapshot: snapshot)
  }

  /// Returns the focused workspace background color.
  static func spaceActiveBackground(snapshot: ConfigSnapshot) -> Color {
    Color(hex: snapshot.builtins.spaces.colors.activeBackgroundHex, snapshot: snapshot)
  }

  /// Returns the inactive workspace background color.
  static func spaceInactiveBackground(snapshot: ConfigSnapshot) -> Color {
    Color(hex: snapshot.builtins.spaces.colors.inactiveBackgroundHex, snapshot: snapshot)
  }

  /// Returns the focused workspace border color.
  static func spaceActiveBorder(snapshot: ConfigSnapshot) -> Color {
    Color(hex: snapshot.builtins.spaces.colors.activeBorderHex, snapshot: snapshot)
  }

  /// Returns the inactive workspace border color.
  static func spaceInactiveBorder(snapshot: ConfigSnapshot) -> Color {
    Color(hex: snapshot.builtins.spaces.colors.inactiveBorderHex, snapshot: snapshot)
  }

  /// Returns the focused workspace text color.
  static func spaceFocusedText(snapshot: ConfigSnapshot) -> Color {
    Color(hex: snapshot.builtins.spaces.text.focusedColorHex, snapshot: snapshot)
  }

  /// Returns the inactive workspace text color.
  static func spaceInactiveText(snapshot: ConfigSnapshot) -> Color {
    Color(hex: snapshot.builtins.spaces.text.inactiveColorHex, snapshot: snapshot)
  }
}
