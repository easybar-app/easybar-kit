import EasyBarShared
import Foundation
import SwiftUI

extension Config {
  /// App-level config values.
  struct AppSection {
    struct LuaCommandLimits: Equatable {
      var timeoutSeconds: TimeInterval
      var maxOutputBytes: Int
      var maxAsyncJobs: Int
    }

    var runtimeDirectory: String
    var widgetsPath: String
    var luaPath: String
    var luaSocketPath: String
    var environment: [String: String]
    var watchConfigFile: Bool
    var lockDirectory: String
    var widgetEditorStubPath: String
    var develop: Bool
    var showMenuBarIcon: Bool
    var luaCommandLimits: LuaCommandLimits
  }

  /// Logging config values.
  struct LoggingSection {
    var enabled: Bool
    var level: ProcessLogLevel
    var directory: String
  }

  /// Calendar agent config values.
  struct CalendarAgentSection {
    var enabled: Bool
    var socketPath: String
  }

  /// Network agent config values.
  struct NetworkAgentSection {
    var enabled: Bool
    var socketPath: String
    var refreshIntervalSeconds: Double
    var allowUnauthorizedNonSensitiveFields: Bool
  }

  /// Theme color tokens used as defaults and references.
  struct ThemeColors: Equatable {
    var background: String
    var surface: String
    var surfaceElevated: String
    var surfaceHover: String
    var text: String
    var textSecondary: String
    var textTertiary: String
    var muted: String
    var mutedSecondary: String
    var outsideMonth: String
    var accent: String
    var accentSecondary: String
    var accentSoft: String
    var success: String
    var successSecondary: String
    var warning: String
    var orange: String
    var error: String
    var danger: String
    var border: String
    var borderStrong: String
    var borderSubtle: String
    var selectionText: String
    var selectionBackground: String
    var transparent: String
    var overlayOutline: String
    var overlayText: String
  }

  /// Theme config values.
  struct ThemeSection: Equatable {
    var name: String
    var themesDir: String
    var colors: ThemeColors

    /// Bootstrap fallback used before the bundled default theme is parsed.
    static let `default` = ThemeSection(
      name: "default",
      themesDir: "",
      colors: .init(
        background: "#111111",
        surface: "#1a1a1a",
        surfaceElevated: "#2b2b2b",
        surfaceHover: "#202020",
        text: "#ffffff",
        textSecondary: "#d0d0d0",
        textTertiary: "#c0c0c0",
        muted: "#6c7086",
        mutedSecondary: "#8a8a8a",
        outsideMonth: "#6e738d",
        accent: "#91d7e3",
        accentSecondary: "#89B4FA",
        accentSoft: "#8bd5ca",
        success: "#a6e3a1",
        successSecondary: "#a6da95",
        warning: "#f9e2af",
        orange: "#fab387",
        error: "#f38ba8",
        danger: "#FF0000",
        border: "#333333",
        borderStrong: "#444444",
        borderSubtle: "#00000000",
        selectionText: "#0B1020",
        selectionBackground: "#89B4FA",
        transparent: "#00000000",
        overlayOutline: "#000000F0",
        overlayText: "#FFFFFFFF"
      )
    )
  }

  /// Bar layout and color config values.
  struct BarSection {
    var height: CGFloat
    var paddingX: CGFloat
    var extendBehindNotch: Bool
    var backgroundHex: String
    var borderHex: String

    static let `default` = BarSection(
      height: 32,
      paddingX: 10,
      extendBehindNotch: true,
      backgroundHex: ThemeSection.default.colors.background,
      borderHex: ThemeSection.default.colors.transparent
    )
  }
}
