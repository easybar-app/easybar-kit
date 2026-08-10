import Darwin
import EasyBarShared
import Foundation
import XCTest

@testable import EasyBarKit

final class ConfigLoaderBuiltinTests: ConfigLoaderTestCase {
  func testReloadAppliesInboxConfiguration() throws {
    let config = Config.makeUnloadedConfig()
    let configFileURL = tempDirectoryURL.appendingPathComponent("inbox.toml")
    try writeConfig(
      """
      [builtins.inbox]
      enabled = true
      position = "left"
      order = 7

      [builtins.inbox.style]
      unread_icon = "IN"
      read_icon = "OUT"
      unread_icon_color = "#eeeeee"
      read_icon_color = "#123456"
      unread_count_color = "#dddddd"
      background_color = "#121212"
      border_color = "#232323"
      border_width = 2
      corner_radius = 9
      margin_x = 1
      margin_y = 2
      padding_x = 3
      padding_y = 4
      spacing = 5
      opacity = 0.75

      [builtins.inbox.colors]
      background = "#010101"
      border = "#020202"
      title = "#030303"
      text = "#040404"
      muted = "#050505"
      item_background = "#060606"
      action = "#070707"
      info = "#080808"
      success = "#090909"
      warning = "#101010"
      error = "#111111"

      [builtins.inbox.content]
      group_by = "date"
      sort_by = "severity"
      sort_descending = false
      show_unread_count = false
      use_inactive_style_when_read = false
      show_when_empty = false
      show_source_actions = false
      show_refresh_all = false
      refresh_all_icon = "arrow.trianglehead.2.clockwise"
      refresh_all_tooltip = "Sync every inbox"
      show_mark_all_read = false
      mark_all_read_icon = "checkmark.circle"
      mark_all_read_tooltip = "Read everything"
      show_dismiss_all = false
      dismiss_all_icon = "xmark.square"
      dismiss_all_tooltip = "Dismiss everything"
      popup_width = 480
      popup_max_height = 600
      max_items = 25
      """,
      to: configFileURL
    )
    setEnvironmentValue(configFileURL.path, for: SharedEnvironmentKeys.configPath)

    XCTAssertNil(config.reload())
    XCTAssertEqual(config.builtinInbox.placement.position, .left)
    XCTAssertEqual(config.builtinInbox.placement.order, 7)
    XCTAssertEqual(config.builtinInbox.style.unreadIcon, "IN")
    XCTAssertEqual(config.builtinInbox.style.readIcon, "OUT")
    XCTAssertEqual(config.builtinInbox.style.unreadIconColorHex, "#eeeeee")
    XCTAssertEqual(config.builtinInbox.style.readIconColorHex, "#123456")
    XCTAssertEqual(config.builtinInbox.style.unreadCountColorHex, "#dddddd")
    XCTAssertEqual(config.builtinInbox.style.chrome.backgroundColorHex, "#121212")
    XCTAssertEqual(config.builtinInbox.style.chrome.borderColorHex, "#232323")
    XCTAssertEqual(config.builtinInbox.style.chrome.borderWidth, 2)
    XCTAssertEqual(config.builtinInbox.style.chrome.cornerRadius, 9)
    XCTAssertEqual(config.builtinInbox.style.chrome.marginX, 1)
    XCTAssertEqual(config.builtinInbox.style.chrome.marginY, 2)
    XCTAssertEqual(config.builtinInbox.style.chrome.paddingX, 3)
    XCTAssertEqual(config.builtinInbox.style.chrome.paddingY, 4)
    XCTAssertEqual(config.builtinInbox.style.chrome.spacing, 5)
    XCTAssertEqual(config.builtinInbox.style.chrome.opacity, 0.75)
    XCTAssertEqual(config.builtinInbox.groupBy, .date)
    XCTAssertEqual(config.builtinInbox.sortBy, .severity)
    XCTAssertFalse(config.builtinInbox.sortDescending)
    XCTAssertFalse(config.builtinInbox.showUnreadCount)
    XCTAssertFalse(config.builtinInbox.useInactiveStyleWhenRead)
    XCTAssertFalse(config.builtinInbox.showWhenEmpty)
    XCTAssertFalse(config.builtinInbox.showSourceActions)
    XCTAssertFalse(config.builtinInbox.showRefreshAll)
    XCTAssertEqual(config.builtinInbox.refreshAllIcon, "arrow.trianglehead.2.clockwise")
    XCTAssertEqual(config.builtinInbox.refreshAllTooltip, "Sync every inbox")
    XCTAssertFalse(config.builtinInbox.showMarkAllRead)
    XCTAssertEqual(config.builtinInbox.markAllReadIcon, "checkmark.circle")
    XCTAssertEqual(config.builtinInbox.markAllReadTooltip, "Read everything")
    XCTAssertFalse(config.builtinInbox.showDismissAll)
    XCTAssertEqual(config.builtinInbox.dismissAllIcon, "xmark.square")
    XCTAssertEqual(config.builtinInbox.dismissAllTooltip, "Dismiss everything")
    XCTAssertEqual(config.builtinInbox.popupWidth, 480)
    XCTAssertEqual(config.builtinInbox.popupMaxHeight, 600)
    XCTAssertEqual(config.builtinInbox.popupBackgroundColorHex, "#010101")
    XCTAssertEqual(config.builtinInbox.popupBorderColorHex, "#020202")
    XCTAssertEqual(config.builtinInbox.popupTitleColorHex, "#030303")
    XCTAssertEqual(config.builtinInbox.popupTextColorHex, "#040404")
    XCTAssertEqual(config.builtinInbox.popupMutedColorHex, "#050505")
    XCTAssertEqual(config.builtinInbox.popupItemBackgroundColorHex, "#060606")
    XCTAssertEqual(config.builtinInbox.popupActionColorHex, "#070707")
    XCTAssertEqual(config.builtinInbox.infoColorHex, "#080808")
    XCTAssertEqual(config.builtinInbox.successColorHex, "#090909")
    XCTAssertEqual(config.builtinInbox.warningColorHex, "#101010")
    XCTAssertEqual(config.builtinInbox.errorColorHex, "#111111")
    XCTAssertEqual(config.builtinInbox.maxItems, 25)
  }

  func testReloadRejectsEmptyInboxActionTooltip() throws {
    let config = Config.makeUnloadedConfig()
    let configFileURL = tempDirectoryURL.appendingPathComponent("empty-inbox-tooltip.toml")
    try writeConfig(
      """
      [builtins.inbox.content]
      mark_all_read_tooltip = "   "
      """,
      to: configFileURL
    )
    setEnvironmentValue(configFileURL.path, for: SharedEnvironmentKeys.configPath)

    let error = config.reload()

    guard case .invalidValue(let path, let message)? = error as? ConfigError else {
      return XCTFail("Expected invalidValue ConfigError, got \(String(describing: error))")
    }
    XCTAssertEqual(path, "builtins.inbox.content.mark_all_read_tooltip")
    XCTAssertEqual(message, "expected a non-empty string")
  }

  /// Verifies that a missing config file still loads a useful default bar.
  func testReloadUsesUsefulBuiltinsWhenConfigFileIsMissing() throws {
    let config = Config.makeUnloadedConfig()
    let configFileURL = tempDirectoryURL.appendingPathComponent("missing-config.toml")

    setEnvironmentValue(configFileURL.path, for: SharedEnvironmentKeys.configPath)

    let error = config.reload()

    XCTAssertNil(error)
    XCTAssertTrue(config.builtinSpaces.enabled)
    XCTAssertTrue(config.builtinBattery.enabled)
    XCTAssertTrue(config.builtinWiFi.enabled)
    XCTAssertTrue(config.builtinCalendar.enabled)
  }

  /// Verifies that reload applies config file overrides and creates required directories.
  func testReloadAppliesConfigFileOverridesAndCreatesRequiredDirectories() throws {
    let config = Config.makeUnloadedConfig()
    let configFileURL = tempDirectoryURL.appendingPathComponent("config.toml")
    let widgetsDirectory = tempDirectoryURL.appendingPathComponent("widgets").path
    let lockDirectory = tempDirectoryURL.appendingPathComponent("locks").path
    let loggingDirectory = tempDirectoryURL.appendingPathComponent("logs").path
    let runtimeDirectory = tempDirectoryURL.appendingPathComponent("runtime").path
    let luaSocketPath = URL(fileURLWithPath: runtimeDirectory)
      .appendingPathComponent("lua.sock")
      .path
    let widgetEditorStubPath = tempDirectoryURL.appendingPathComponent("generated/api.lua").path
    let calendarSocketPath = URL(fileURLWithPath: runtimeDirectory)
      .appendingPathComponent("calendar.sock")
      .path
    let networkSocketPath = URL(fileURLWithPath: runtimeDirectory)
      .appendingPathComponent("network.sock")
      .path

    try writeConfig(
      """
      [app]
      runtime_dir = "\(runtimeDirectory)"
      widgets_dir = "\(widgetsDirectory)"
      lua_path = "/usr/local/bin/lua"
      lua_socket_path = "\(luaSocketPath)"
      watch_config = false
      lock_dir = "\(lockDirectory)"
      widget_editor_stub_path = "\(widgetEditorStubPath)"
      develop = true
      show_menu_bar_icon = false

      [app.env]
      PATH = "/custom/bin"
      FOO = "bar"

      [logging]
      enabled = true
      level = "debug"
      directory = "\(loggingDirectory)"

      [agents.calendar]
      enabled = false
      socket_path = "\(calendarSocketPath)"

      [agents.network]
      enabled = false
      socket_path = "\(networkSocketPath)"
      refresh_interval_seconds = 15
      allow_unauthorized_non_sensitive_fields = true

      [bar]
      height = 40
      padding_x = 22
      extend_behind_notch = false

      [bar.colors]
      background = "#123456"
      border = "#abcdef"
      """,
      to: configFileURL
    )

    setEnvironmentValue(configFileURL.path, for: SharedEnvironmentKeys.configPath)

    let error = config.reload()

    XCTAssertNil(error)
    XCTAssertEqual(config.runtimeDirectory, runtimeDirectory)
    XCTAssertEqual(config.widgetsPath, widgetsDirectory)
    XCTAssertEqual(config.luaPath, "/usr/local/bin/lua")
    XCTAssertEqual(config.luaSocketPath, luaSocketPath)
    XCTAssertFalse(config.watchConfigFile)
    XCTAssertEqual(config.lockDirectory, lockDirectory)
    XCTAssertEqual(config.widgetEditorStubPath, widgetEditorStubPath)
    XCTAssertTrue(config.develop)
    XCTAssertFalse(config.showMenuBarIcon)

    XCTAssertEqual(config.appSection.environment[SharedEnvironmentKeys.path], "/custom/bin")
    XCTAssertEqual(config.appSection.environment["FOO"], "bar")

    XCTAssertTrue(config.loggingEnabled)
    XCTAssertEqual(config.loggingLevel, .debug)
    XCTAssertEqual(config.loggingDirectory, loggingDirectory)

    XCTAssertFalse(config.calendarAgentEnabled)
    XCTAssertEqual(config.calendarAgentSocketPath, calendarSocketPath)
    XCTAssertFalse(config.networkAgentEnabled)
    XCTAssertEqual(config.networkAgentSocketPath, networkSocketPath)
    XCTAssertEqual(config.networkAgentRefreshIntervalSeconds, 15)
    XCTAssertTrue(config.networkAgentAllowUnauthorizedNonSensitiveFields)

    XCTAssertEqual(config.barHeight, 40)
    XCTAssertEqual(config.barPaddingX, 22)
    XCTAssertFalse(config.barExtendBehindNotch)
    XCTAssertEqual(config.barBackgroundHex, "#123456")
    XCTAssertEqual(config.barBorderHex, "#abcdef")

    XCTAssertTrue(FileManager.default.fileExists(atPath: widgetsDirectory))
    XCTAssertTrue(FileManager.default.fileExists(atPath: lockDirectory))
    XCTAssertTrue(FileManager.default.fileExists(atPath: loggingDirectory))
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: URL(fileURLWithPath: widgetEditorStubPath).deletingLastPathComponent().path
      )
    )
    XCTAssertTrue(FileManager.default.fileExists(atPath: runtimeDirectory))
  }

  func testReloadRejectsNegativeNetworkAgentRefreshInterval() throws {
    let config = Config.makeUnloadedConfig()
    let configFileURL = tempDirectoryURL.appendingPathComponent(
      "negative-network-refresh-interval.toml"
    )

    try writeConfig(
      """
      [agents.network]
      refresh_interval_seconds = -1
      """,
      to: configFileURL
    )

    setEnvironmentValue(configFileURL.path, for: SharedEnvironmentKeys.configPath)

    let error = config.reload()

    guard case .invalidValue(let path, let message)? = error as? ConfigError else {
      return XCTFail("Expected invalidValue ConfigError, got \(String(describing: error))")
    }

    XCTAssertEqual(path, "agents.network.refresh_interval_seconds")
    XCTAssertEqual(message, "expected a value greater than or equal to 0")
  }

  /// Verifies that reload applies month popup agenda layout overrides.
  func testReloadAppliesMonthPopupAgendaLayoutOverride() throws {
    let config = Config.makeUnloadedConfig()
    let configFileURL = tempDirectoryURL.appendingPathComponent("calendar-layout.toml")

    try writeConfig(
      """
      [builtins.calendar]
      enabled = true

      [builtins.calendar.month.popup.agenda]
      layout = "appointments_calendar_vertical"
      """,
      to: configFileURL
    )

    setEnvironmentValue(configFileURL.path, for: SharedEnvironmentKeys.configPath)

    let error = config.reload()

    XCTAssertNil(error)
    XCTAssertEqual(
      config.builtinCalendar.month.popup.layout,
      .appointmentsCalendarVertical
    )
    XCTAssertEqual(
      config.builtinCalendar.calendarMonthPopupUIConfig.layout,
      .appointmentsCalendarVertical
    )
  }

  func testReloadAppliesMonthTodayMarkerOverrides() throws {
    let config = Config.makeUnloadedConfig()
    let configFileURL = tempDirectoryURL.appendingPathComponent("calendar-today-marker.toml")

    try writeConfig(
      """
      [builtins.calendar.month.popup.calendar]
      today_marker_variant = "open_loop"
      today_marker_size = 24.5

      [builtins.calendar.month.popup.today_button]
      padding_x = 9
      padding_y = 3
      margin_x = 2
      margin_y = 1
      """,
      to: configFileURL
    )

    setEnvironmentValue(configFileURL.path, for: SharedEnvironmentKeys.configPath)

    XCTAssertNil(config.reload())
    XCTAssertEqual(config.builtinCalendar.month.popup.todayMarkerVariant, .openLoop)
    XCTAssertEqual(config.builtinCalendar.month.popup.todayMarkerSize, 24.5)
    XCTAssertEqual(config.builtinCalendar.month.popup.todayButtonPaddingX, 9)
    XCTAssertEqual(config.builtinCalendar.month.popup.todayButtonPaddingY, 3)
    XCTAssertEqual(config.builtinCalendar.month.popup.todayButtonMarginX, 2)
    XCTAssertEqual(config.builtinCalendar.month.popup.todayButtonMarginY, 1)
    XCTAssertEqual(config.builtinCalendar.calendarMonthPopupUIConfig.todayMarkerVariant, .openLoop)
    XCTAssertEqual(config.builtinCalendar.calendarMonthPopupUIConfig.todayMarkerSize, 24.5)
    XCTAssertEqual(config.builtinCalendar.calendarMonthPopupUIConfig.todayButtonPaddingX, 9)
    XCTAssertEqual(config.builtinCalendar.calendarMonthPopupUIConfig.todayButtonPaddingY, 3)
    XCTAssertEqual(config.builtinCalendar.calendarMonthPopupUIConfig.todayButtonMarginX, 2)
    XCTAssertEqual(config.builtinCalendar.calendarMonthPopupUIConfig.todayButtonMarginY, 1)
  }

  func testReloadUsesDefaultCalendarMeetingURLPatternsWhenSettingIsOmitted() throws {
    let config = Config.makeUnloadedConfig()
    let configFileURL = tempDirectoryURL.appendingPathComponent(
      "calendar-meeting-urls-default.toml"
    )

    try writeConfig(
      """
      [builtins.calendar.appointments]
      show_location = false
      """,
      to: configFileURL
    )

    setEnvironmentValue(configFileURL.path, for: SharedEnvironmentKeys.configPath)

    XCTAssertNil(config.reload())
    XCTAssertEqual(
      config.builtinCalendar.appointments.meetingURLPatterns,
      CalendarMeetingURLMatcher.defaultPatterns
    )
  }

  func testReloadAllowsEmptyCalendarMeetingURLPatterns() throws {
    let config = Config.makeUnloadedConfig()
    let configFileURL = tempDirectoryURL.appendingPathComponent(
      "calendar-meeting-urls-disabled.toml"
    )

    try writeConfig(
      """
      [builtins.calendar.appointments]
      meeting_url_patterns = []
      """,
      to: configFileURL
    )

    setEnvironmentValue(configFileURL.path, for: SharedEnvironmentKeys.configPath)

    XCTAssertNil(config.reload())
    XCTAssertEqual(config.builtinCalendar.appointments.meetingURLPatterns, [])
  }

  func testReloadAppliesCalendarMeetingURLPatterns() throws {
    let config = Config.makeUnloadedConfig()
    let configFileURL = tempDirectoryURL.appendingPathComponent("calendar-meeting-urls.toml")

    try writeConfig(
      """
      [builtins.calendar.appointments]
      meeting_url_patterns = [" Video.Example.com ", "", "video.example.com", "call.example.net"]
      """,
      to: configFileURL
    )

    setEnvironmentValue(configFileURL.path, for: SharedEnvironmentKeys.configPath)

    XCTAssertNil(config.reload())
    XCTAssertEqual(
      config.builtinCalendar.appointments.meetingURLPatterns,
      ["video.example.com", "call.example.net"]
    )
  }

  /// Verifies that reload failure keeps previous bar and builtin configuration.
  func testReloadFailureKeepsPreviousBarAndBuiltinConfiguration() throws {
    let config = Config.makeUnloadedConfig()
    let configFileURL = tempDirectoryURL.appendingPathComponent("reload-config.toml")

    try writeConfig(
      """
      [bar]
      height = 44

      [bar.colors]
      background = "#224466"

      [builtins.time]
      enabled = true
      position = "left"

      [builtins.time.content]
      format = "HH:mm:ss"

      [builtins.cpu]
      enabled = true

      [builtins.cpu.content]
      history_size = 24
      """,
      to: configFileURL
    )

    setEnvironmentValue(configFileURL.path, for: SharedEnvironmentKeys.configPath)
    XCTAssertNil(config.reload())

    XCTAssertEqual(config.barHeight, 44)
    XCTAssertEqual(config.barBackgroundHex, "#224466")
    XCTAssertTrue(config.builtinTime.placement.enabled)
    XCTAssertEqual(config.builtinTime.placement.position, .left)
    XCTAssertEqual(config.builtinTime.content.format, "HH:mm:ss")
    XCTAssertTrue(config.builtinCPU.enabled)
    XCTAssertEqual(config.builtinCPU.historySize, 24)

    try writeConfig(
      """
      [bar]
      height = 28

      [builtins.time]
      position = "sideways"
      """,
      to: configFileURL
    )

    let error = config.reload()

    guard let configError = error as? ConfigError else {
      return XCTFail("Expected ConfigError, got \(String(describing: error))")
    }

    XCTAssertEqual(configError.configPath, "builtins.time.position")
    XCTAssertEqual(config.barHeight, 44)
    XCTAssertEqual(config.barBackgroundHex, "#224466")
    XCTAssertTrue(config.builtinTime.placement.enabled)
    XCTAssertEqual(config.builtinTime.placement.position, .left)
    XCTAssertEqual(config.builtinTime.content.format, "HH:mm:ss")
    XCTAssertTrue(config.builtinCPU.enabled)
    XCTAssertEqual(config.builtinCPU.historySize, 24)
  }

  /// Verifies that reload returns invalid type for bar height string value.
  func testReloadReturnsInvalidTypeForBarHeightStringValue() throws {
    let config = Config.makeUnloadedConfig()
    let configFileURL = tempDirectoryURL.appendingPathComponent("invalid-bar-type.toml")

    try writeConfig(
      """
      [bar]
      height = "tall"
      """,
      to: configFileURL
    )

    setEnvironmentValue(configFileURL.path, for: SharedEnvironmentKeys.configPath)

    let error = config.reload()

    guard case .invalidType(let path, let expected, let actual)? = error as? ConfigError else {
      return XCTFail("Expected invalidType ConfigError, got \(String(describing: error))")
    }

    XCTAssertEqual(path, "bar.height")
    XCTAssertEqual(expected, "integer")
    XCTAssertEqual(actual, "string(tall)")
  }

  func testReloadRejectsNegativeBarHeight() throws {
    let config = Config.makeUnloadedConfig()
    let configFileURL = tempDirectoryURL.appendingPathComponent("invalid-bar-height.toml")

    try writeConfig(
      """
      [bar]
      height = -1
      """,
      to: configFileURL
    )

    setEnvironmentValue(configFileURL.path, for: SharedEnvironmentKeys.configPath)

    let error = config.reload()

    guard case .invalidValue(let path, let message)? = error as? ConfigError else {
      return XCTFail("Expected invalidValue ConfigError, got \(String(describing: error))")
    }

    XCTAssertEqual(path, "bar.height")
    XCTAssertEqual(message, "expected a value greater than or equal to 0")
  }

  func testReloadRejectsNegativeBarPaddingX() throws {
    let config = Config.makeUnloadedConfig()
    let configFileURL = tempDirectoryURL.appendingPathComponent("invalid-bar-padding.toml")

    try writeConfig(
      """
      [bar]
      padding_x = -1
      """,
      to: configFileURL
    )

    setEnvironmentValue(configFileURL.path, for: SharedEnvironmentKeys.configPath)

    let error = config.reload()

    guard case .invalidValue(let path, let message)? = error as? ConfigError else {
      return XCTFail("Expected invalidValue ConfigError, got \(String(describing: error))")
    }

    XCTAssertEqual(path, "bar.padding_x")
    XCTAssertEqual(message, "expected a value greater than or equal to 0")
  }

  /// Verifies that reload normalizes enum values with whitespace for builtins.
  func testReloadNormalizesEnumValuesWithWhitespaceForBuiltins() throws {
    let config = Config.makeUnloadedConfig()
    let configFileURL = tempDirectoryURL.appendingPathComponent("normalized-builtins.toml")

    try writeConfig(
      """
      [builtins.time]
      enabled = true
      position = " Left "
      """,
      to: configFileURL
    )

    setEnvironmentValue(configFileURL.path, for: SharedEnvironmentKeys.configPath)

    let error = config.reload()

    XCTAssertNil(error)
    XCTAssertTrue(config.builtinTime.placement.enabled)
    XCTAssertEqual(config.builtinTime.placement.position, .left)
  }

  /// Verifies that reload applies Wi-Fi popup style from the canonical table.
  func testReloadAppliesWiFiPopupStyle() throws {
    let config = Config.makeUnloadedConfig()
    let configFileURL = tempDirectoryURL.appendingPathComponent("wifi-popup-style.toml")

    try writeConfig(
      """
      [builtins.wifi.popup]
      text_color = "#101010"
      background_color = "#202020"
      border_color = "#303030"
      border_width = 2
      corner_radius = 10
      padding_x = 12
      padding_y = 7
      margin_x = 3
      margin_y = 9
      """,
      to: configFileURL
    )

    setEnvironmentValue(configFileURL.path, for: SharedEnvironmentKeys.configPath)

    let error = config.reload()

    XCTAssertNil(error)
    XCTAssertEqual(config.builtinWiFi.popup.textColorHex, "#101010")
    XCTAssertEqual(config.builtinWiFi.popup.backgroundColorHex, "#202020")
    XCTAssertEqual(config.builtinWiFi.popup.borderColorHex, "#303030")
    XCTAssertEqual(config.builtinWiFi.popup.borderWidth, 2)
    XCTAssertEqual(config.builtinWiFi.popup.cornerRadius, 10)
    XCTAssertEqual(config.builtinWiFi.popup.paddingX, 12)
    XCTAssertEqual(config.builtinWiFi.popup.paddingY, 7)
    XCTAssertEqual(config.builtinWiFi.popup.marginX, 3)
    XCTAssertEqual(config.builtinWiFi.popup.marginY, 9)
  }

  /// Verifies that reload returns error for unknown builtin group reference.
  func testReloadReturnsErrorForUnknownBuiltinGroupReference() throws {
    let config = Config.makeUnloadedConfig()
    let configFileURL = tempDirectoryURL.appendingPathComponent("unknown-group.toml")

    try writeConfig(
      """
      [builtins.groups.clock_row]
      enabled = true

      [builtins.time]
      enabled = true
      group = "missing"
      """,
      to: configFileURL
    )

    setEnvironmentValue(configFileURL.path, for: SharedEnvironmentKeys.configPath)

    let error = config.reload()

    guard let configError = error as? ConfigError else {
      return XCTFail("Expected ConfigError, got \(String(describing: error))")
    }

    XCTAssertEqual(configError.configPath, "builtins.time.group")
    XCTAssertEqual(
      configError.detail,
      "unknown built-in group 'missing'; expected one of clock_row"
    )
  }

  /// Verifies that reload returns error for nested builtin group reference.
  func testReloadReturnsErrorForNestedBuiltinGroupReference() throws {
    let config = Config.makeUnloadedConfig()
    let configFileURL = tempDirectoryURL.appendingPathComponent("nested-group.toml")

    try writeConfig(
      """
      [builtins.groups.outer]
      enabled = true

      [builtins.groups.inner]
      enabled = true
      group = "outer"
      """,
      to: configFileURL
    )

    setEnvironmentValue(configFileURL.path, for: SharedEnvironmentKeys.configPath)

    let error = config.reload()

    guard let configError = error as? ConfigError else {
      return XCTFail("Expected ConfigError, got \(String(describing: error))")
    }

    XCTAssertEqual(configError.configPath, "builtins.groups.inner.group")
    XCTAssertEqual(configError.detail, "built-in groups cannot be nested")
  }

}

extension ConfigLoaderBuiltinTests {
  /// Verifies that the volume slider range must be ordered before reaching SwiftUI.
  func testReloadRejectsInvalidVolumeSliderRange() throws {
    let config = Config.makeUnloadedConfig()
    let configFileURL = tempDirectoryURL.appendingPathComponent("invalid-volume-range.toml")

    try writeConfig(
      """
      [builtins.volume.content]
      min = 100
      max = 0
      """,
      to: configFileURL
    )

    setEnvironmentValue(configFileURL.path, for: SharedEnvironmentKeys.configPath)

    let error = config.reload()

    guard case .invalidValue(let path, let message)? = error as? ConfigError else {
      return XCTFail("Expected invalidValue ConfigError, got \(String(describing: error))")
    }

    XCTAssertEqual(path, "builtins.volume.content.max")
    XCTAssertEqual(message, "expected a value greater than builtins.volume.content.min")
  }

  /// Verifies that the volume slider maximum stays inside the supported display range.
  func testReloadRejectsOutOfRangeVolumeSliderMaximum() throws {
    let config = Config.makeUnloadedConfig()
    let configFileURL = tempDirectoryURL.appendingPathComponent("invalid-volume-maximum.toml")

    try writeConfig(
      """
      [builtins.volume.content]
      max = 101
      """,
      to: configFileURL
    )

    setEnvironmentValue(configFileURL.path, for: SharedEnvironmentKeys.configPath)

    let error = config.reload()

    guard case .invalidValue(let path, let message)? = error as? ConfigError else {
      return XCTFail("Expected invalidValue ConfigError, got \(String(describing: error))")
    }

    XCTAssertEqual(path, "builtins.volume.content.max")
    XCTAssertEqual(message, "expected a value from 0 to 100")
  }

  /// Verifies that the volume slider step cannot be zero or negative.
  func testReloadRejectsInvalidVolumeSliderStep() throws {
    let config = Config.makeUnloadedConfig()
    let configFileURL = tempDirectoryURL.appendingPathComponent("invalid-volume-step.toml")

    try writeConfig(
      """
      [builtins.volume.content]
      step = 0
      """,
      to: configFileURL
    )

    setEnvironmentValue(configFileURL.path, for: SharedEnvironmentKeys.configPath)

    let error = config.reload()

    guard case .invalidValue(let path, let message)? = error as? ConfigError else {
      return XCTFail("Expected invalidValue ConfigError, got \(String(describing: error))")
    }

    XCTAssertEqual(path, "builtins.volume.content.step")
    XCTAssertEqual(message, "expected a value greater than 0 and less than or equal to 100")
  }

  /// Verifies that the configured volume slider width must be positive.
  func testReloadRejectsInvalidVolumeSliderWidth() throws {
    let config = Config.makeUnloadedConfig()
    let configFileURL = tempDirectoryURL.appendingPathComponent("invalid-volume-width.toml")

    try writeConfig(
      """
      [builtins.volume.slider]
      width = 0
      """,
      to: configFileURL
    )

    setEnvironmentValue(configFileURL.path, for: SharedEnvironmentKeys.configPath)

    let error = config.reload()

    guard case .invalidValue(let path, let message)? = error as? ConfigError else {
      return XCTFail("Expected invalidValue ConfigError, got \(String(describing: error))")
    }

    XCTAssertEqual(path, "builtins.volume.slider.width")
    XCTAssertEqual(message, "expected a value greater than 0")
  }
}

extension ConfigLoaderBuiltinTests {
  func testCalendarComposerLabelOverrideSectionsAreOptional() throws {
    let config = Config.makeUnloadedConfig()
    let configFileURL = tempDirectoryURL.appendingPathComponent("config.toml")

    setEnvironmentValue(configFileURL.path, for: SharedEnvironmentKeys.configPath)
    try writeConfig(
      """
      [builtins.calendar.composer]
      create_title = "Create"
      """,
      to: configFileURL
    )

    let error = config.reload()

    XCTAssertNil(error)
    XCTAssertEqual(config.builtinCalendar.composer.createTitle, "Create")
    XCTAssertTrue(config.builtinCalendar.composer.alertLabels.isEmpty)
    XCTAssertTrue(config.builtinCalendar.composer.travelTimeLabels.isEmpty)
  }

  func testCalendarComposerLabelOverrideSectionsCanPartiallyOverrideSystemLabels() throws {
    let config = Config.makeUnloadedConfig()
    let configFileURL = tempDirectoryURL.appendingPathComponent("config.toml")

    setEnvironmentValue(configFileURL.path, for: SharedEnvironmentKeys.configPath)
    try writeConfig(
      """
      [builtins.calendar.composer.alert_labels]
      5_minutes = "Five before"

      [builtins.calendar.composer.travel_time_labels]
      90_minutes = "Ninety travel"
      """,
      to: configFileURL
    )

    let error = config.reload()

    XCTAssertNil(error)
    XCTAssertEqual(config.builtinCalendar.composer.alertLabels, ["5_minutes": "Five before"])
    XCTAssertEqual(
      config.builtinCalendar.composer.travelTimeLabels, ["90_minutes": "Ninety travel"])
  }
}
