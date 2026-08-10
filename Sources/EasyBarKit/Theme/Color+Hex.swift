import SwiftUI

/// Hex color helpers for config strings.
extension String {

  /// Returns the hex text normalized for shared color checks.
  var normalizedHexColor: String {
    trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "#", with: "")
      .uppercased()
  }

  /// Returns whether this string is a supported hex color literal.
  var isValidHexColorLiteral: Bool {
    HexColorComponents(hex: self) != nil
  }

  /// Returns whether this hex string is a fully transparent color.
  var isFullyTransparentHexColor: Bool {
    return normalizedHexColor.isEmpty || normalizedHexColor == "00000000"
  }
}

/// Parsed color components for `RRGGBB` and `RRGGBBAA` strings.
private struct HexColorComponents {
  let red: Double
  let green: Double
  let blue: Double
  let alpha: Double

  init?(hex rawValue: String) {
    let hex = rawValue.normalizedHexColor
    let hexDigits = CharacterSet(charactersIn: "0123456789ABCDEF")

    guard hex.count == 6 || hex.count == 8,
      hex.unicodeScalars.allSatisfy({ hexDigits.contains($0) }),
      let value = UInt64(hex, radix: 16)
    else {
      return nil
    }

    switch hex.count {
    case 6:
      red = Double((value >> 16) & 0xff) / 255
      green = Double((value >> 8) & 0xff) / 255
      blue = Double(value & 0xff) / 255
      alpha = 1

    case 8:
      red = Double((value >> 24) & 0xff) / 255
      green = Double((value >> 16) & 0xff) / 255
      blue = Double((value >> 8) & 0xff) / 255
      alpha = Double(value & 0xff) / 255

    default:
      return nil
    }
  }
}

/// SwiftUI color helpers.
extension Color {

  /// Creates a color from `RRGGBB` or `RRGGBBAA` text.
  init(hex: String) {
    guard let components = HexColorComponents(hex: hex) else {
      assertionFailure("Invalid hex color '\(hex)'. Use RRGGBB or RRGGBBAA.")
      self.init(.sRGB, red: 1, green: 0, blue: 1, opacity: 1)
      return
    }

    self.init(
      .sRGB,
      red: components.red,
      green: components.green,
      blue: components.blue,
      opacity: components.alpha
    )
  }

  /// Creates a color from `RRGGBB`, `RRGGBBAA`, or `theme.<token>` text.
  init(hex: String, snapshot: ConfigSnapshot) {
    self.init(hex: snapshot.resolvedColorHex(hex))
  }
}
