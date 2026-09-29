import EasyBarShared
import Foundation
import SwiftUI

extension Config {
  /// App-level config values.
  struct AppSection {
    /// Stores Lua command limits data.
    struct LuaCommandLimits: Equatable {
      /// The timeout seconds for this Lua command limits.
      var timeoutSeconds: TimeInterval
      /// The max output bytes for this Lua command limits.
      var maxOutputBytes: Int
      /// The max async jobs for this Lua command limits.
      var maxAsyncJobs: Int
    }

    /// The runtime directory for this app section.
    var runtimeDirectory: String
    /// The widgets path for this app section.
    var widgetsPath: String
    /// The Lua path for this app section.
    var luaPath: String
    /// The Lua socket path for this app section.
    var luaSocketPath: String
    /// The environment for this app section.
    var environment: [String: String]
    /// Whether the watch config file option is enabled for this app section.
    var watchConfigFile: Bool
    /// The lock directory for this app section.
    var lockDirectory: String
    /// The widget editor stub path for this app section.
    var widgetEditorStubPath: String
    /// Whether the develop option is enabled for this app section.
    var develop: Bool
    /// Whether this app section shows menu bar icon.
    var showMenuBarIcon: Bool
    /// The Lua command limits for this app section.
    var luaCommandLimits: LuaCommandLimits
  }

  /// Logging config values.
  struct LoggingSection {
    /// Whether this logging section is enabled.
    var enabled: Bool
    /// The level for this logging section.
    var level: ProcessLogLevel
    /// The directory for this logging section.
    var directory: String
  }

  /// Calendar agent config values.
  struct CalendarAgentSection {
    /// Whether this calendar agent section is enabled.
    var enabled: Bool
    /// The socket path for this calendar agent section.
    var socketPath: String
  }

  /// Network agent config values.
  struct NetworkAgentSection {
    /// Whether this network agent section is enabled.
    var enabled: Bool
    /// The socket path for this network agent section.
    var socketPath: String
    /// The refresh interval seconds for this network agent section.
    var refreshIntervalSeconds: Double
    /// Whether the allow unauthorized non sensitive fields option is enabled for this network agent section.
    var allowUnauthorizedNonSensitiveFields: Bool
  }

  /// Theme color tokens used as defaults and references.
  struct ThemeColors: Equatable {
    /// The background for this theme colors.
    var background: String
    /// The surface for this theme colors.
    var surface: String
    /// The surface elevated for this theme colors.
    var surfaceElevated: String
    /// The surface hover for this theme colors.
    var surfaceHover: String
    /// The text for this theme colors.
    var text: String
    /// The text secondary for this theme colors.
    var textSecondary: String
    /// The text tertiary for this theme colors.
    var textTertiary: String
    /// The muted for this theme colors.
    var muted: String
    /// The muted secondary for this theme colors.
    var mutedSecondary: String
    /// The outside month for this theme colors.
    var outsideMonth: String
    /// The accent for this theme colors.
    var accent: String
    /// The accent secondary for this theme colors.
    var accentSecondary: String
    /// The accent soft for this theme colors.
    var accentSoft: String
    /// The success for this theme colors.
    var success: String
    /// The success secondary for this theme colors.
    var successSecondary: String
    /// The warning for this theme colors.
    var warning: String
    /// The orange for this theme colors.
    var orange: String
    /// The error for this theme colors.
    var error: String
    /// The danger for this theme colors.
    var danger: String
    /// The border for this theme colors.
    var border: String
    /// The border strong for this theme colors.
    var borderStrong: String
    /// The border subtle for this theme colors.
    var borderSubtle: String
    /// The selection text for this theme colors.
    var selectionText: String
    /// The selection background for this theme colors.
    var selectionBackground: String
    /// The transparent for this theme colors.
    var transparent: String
    /// The overlay outline for this theme colors.
    var overlayOutline: String
    /// The overlay text for this theme colors.
    var overlayText: String
  }

  /// Theme config values.
  struct ThemeSection: Equatable {
    /// The name for this theme section.
    var name: String
    /// The themes dir for this theme section.
    var themesDir: String
    /// The colors for this theme section.
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
    /// The height for this bar section.
    var height: CGFloat
    /// The padding x for this bar section.
    var paddingX: CGFloat
    /// Whether the extend behind notch option is enabled for this bar section.
    var extendBehindNotch: Bool
    /// The background hex for this bar section.
    var backgroundHex: String
    /// The border hex for this bar section.
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
