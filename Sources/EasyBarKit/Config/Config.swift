import Combine
import EasyBarCalendarConfig
import EasyBarShared
import Foundation
import SwiftUI

/// EasyBar configuration store owned by the app service graph.
final class Config: ObservableObject, @unchecked Sendable {
  typealias CalendarPopupMode = EasyBarCalendarConfig.CalendarPopupMode
  typealias MonthCalendarPopupLayout = EasyBarCalendarConfig.MonthCalendarPopupLayout
  typealias CalendarBuiltinConfig = EasyBarCalendarConfig.CalendarBuiltinConfig

  /// Explicit config path override used by staged validation loads.
  private let configPathOverride: String?
  /// Frontend-owned built-in surface selection used to derive presentation defaults.
  let builtInSurfacePolicy: EasyBarBuiltInSurfacePolicy

  /// Context in which config loading failed.
  enum LoadFailureContext: Equatable {
    /// Initial startup could not load config.
    case initialLoad
    /// Reload failed and the previous config stayed active.
    case reloadKeptPreviousConfig
  }

  /// Captures the latest config load failure.
  struct LoadFailureState {
    /// Underlying load or validation error.
    let error: any Error
    /// Load phase where the error occurred.
    let context: LoadFailureContext
  }

  // MARK: - Stored config sections

  var appSection: AppSection
  var loggingSection: LoggingSection
  var calendarAgentSection: CalendarAgentSection
  var networkAgentSection: NetworkAgentSection
  var themeSection: ThemeSection
  var barSection: BarSection

  // MARK: - App accessors

  var runtimeDirectory: String {
    get { appSection.runtimeDirectory }
    set { appSection.runtimeDirectory = newValue }
  }

  var easyBarSocketPath: String {
    SharedPathDefaults.easyBarSocketPath(in: runtimeDirectory)
  }

  var widgetsPath: String {
    get { appSection.widgetsPath }
    set { appSection.widgetsPath = newValue }
  }

  var luaPath: String {
    get { appSection.luaPath }
    set { appSection.luaPath = newValue }
  }

  var luaSocketPath: String {
    get { appSection.luaSocketPath }
    set { appSection.luaSocketPath = newValue }
  }

  var watchConfigFile: Bool {
    get { appSection.watchConfigFile }
    set { appSection.watchConfigFile = newValue }
  }

  var lockDirectory: String {
    get { appSection.lockDirectory }
    set { appSection.lockDirectory = newValue }
  }

  var widgetEditorStubPath: String {
    get { appSection.widgetEditorStubPath }
    set { appSection.widgetEditorStubPath = newValue }
  }

  var develop: Bool {
    get { appSection.develop }
    set { appSection.develop = newValue }
  }

  var showMenuBarIcon: Bool {
    get { appSection.showMenuBarIcon }
    set { appSection.showMenuBarIcon = newValue }
  }

  var luaCommandTimeoutSeconds: TimeInterval {
    get { appSection.luaCommandLimits.timeoutSeconds }
    set { appSection.luaCommandLimits.timeoutSeconds = newValue }
  }

  var luaCommandMaxOutputBytes: Int {
    get { appSection.luaCommandLimits.maxOutputBytes }
    set { appSection.luaCommandLimits.maxOutputBytes = newValue }
  }

  var luaCommandMaxAsyncJobs: Int {
    get { appSection.luaCommandLimits.maxAsyncJobs }
    set { appSection.luaCommandLimits.maxAsyncJobs = newValue }
  }

  var loggingEnabled: Bool {
    get { loggingSection.enabled }
    set { loggingSection.enabled = newValue }
  }

  var loggingLevel: ProcessLogLevel {
    get { loggingSection.level }
    set { loggingSection.level = newValue }
  }

  var loggingDebugEnabled: Bool {
    get { loggingSection.level.allows(.debug) }
    set { loggingSection.level = newValue ? .debug : .info }
  }

  var loggingTraceEnabled: Bool {
    get { loggingSection.level.allows(.trace) }
    set { loggingSection.level = newValue ? .trace : .info }
  }

  var loggingDirectory: String {
    get { loggingSection.directory }
    set { loggingSection.directory = newValue }
  }

  var calendarAgentEnabled: Bool {
    get { calendarAgentSection.enabled }
    set { calendarAgentSection.enabled = newValue }
  }

  var calendarAgentSocketPath: String {
    get { calendarAgentSection.socketPath }
    set { calendarAgentSection.socketPath = newValue }
  }

  var networkAgentEnabled: Bool {
    get { networkAgentSection.enabled }
    set { networkAgentSection.enabled = newValue }
  }

  var networkAgentSocketPath: String {
    get { networkAgentSection.socketPath }
    set { networkAgentSection.socketPath = newValue }
  }

  var networkAgentRefreshIntervalSeconds: Double {
    get { networkAgentSection.refreshIntervalSeconds }
    set { networkAgentSection.refreshIntervalSeconds = newValue }
  }

  var networkAgentAllowUnauthorizedNonSensitiveFields: Bool {
    get { networkAgentSection.allowUnauthorizedNonSensitiveFields }
    set { networkAgentSection.allowUnauthorizedNonSensitiveFields = newValue }
  }

  // MARK: - Theme accessors

  var themeName: String {
    get { themeSection.name }
    set { themeSection.name = newValue }
  }

  var themesDir: String {
    get { themeSection.themesDir }
    set { themeSection.themesDir = newValue }
  }

  var themeColors: ThemeColors {
    get { themeSection.colors }
    set { themeSection.colors = newValue }
  }

  var themeBackgroundHex: String { themeSection.colors.background }
  var themeSurfaceHex: String { themeSection.colors.surface }
  var themeSurfaceElevatedHex: String { themeSection.colors.surfaceElevated }
  var themeSurfaceHoverHex: String { themeSection.colors.surfaceHover }
  var themeTextColorHex: String { themeSection.colors.text }
  var themeTextSecondaryColorHex: String { themeSection.colors.textSecondary }
  var themeTextTertiaryColorHex: String { themeSection.colors.textTertiary }
  var themeMutedColorHex: String { themeSection.colors.muted }
  var themeMutedSecondaryColorHex: String { themeSection.colors.mutedSecondary }
  var themeOutsideMonthColorHex: String { themeSection.colors.outsideMonth }
  var themeAccentColorHex: String { themeSection.colors.accent }
  var themeAccentSecondaryColorHex: String { themeSection.colors.accentSecondary }
  var themeAccentSoftColorHex: String { themeSection.colors.accentSoft }
  var themeSuccessColorHex: String { themeSection.colors.success }
  var themeSuccessSecondaryColorHex: String { themeSection.colors.successSecondary }
  var themeWarningColorHex: String { themeSection.colors.warning }
  var themeOrangeColorHex: String { themeSection.colors.orange }
  var themeErrorColorHex: String { themeSection.colors.error }
  var themeDangerColorHex: String { themeSection.colors.danger }
  var themeBorderColorHex: String { themeSection.colors.border }
  var themeBorderStrongColorHex: String { themeSection.colors.borderStrong }
  var themeBorderSubtleColorHex: String { themeSection.colors.borderSubtle }
  var themeSelectionTextColorHex: String { themeSection.colors.selectionText }
  var themeSelectionBackgroundColorHex: String { themeSection.colors.selectionBackground }
  var themeTransparentColorHex: String { themeSection.colors.transparent }
  var themeOverlayOutlineColorHex: String { themeSection.colors.overlayOutline }
  var themeOverlayTextColorHex: String { themeSection.colors.overlayText }

  // MARK: - Bar accessors

  var barHeight: CGFloat {
    get { barSection.height }
    set { barSection.height = newValue }
  }

  var barPaddingX: CGFloat {
    get { barSection.paddingX }
    set { barSection.paddingX = newValue }
  }

  var barExtendBehindNotch: Bool {
    get { barSection.extendBehindNotch }
    set { barSection.extendBehindNotch = newValue }
  }

  var barBackgroundHex: String {
    get { barSection.backgroundHex }
    set { barSection.backgroundHex = newValue }
  }

  var barBorderHex: String {
    get { barSection.borderHex }
    set { barSection.borderHex = newValue }
  }

  var barShowsBorder: Bool {
    return !barBorderHex.isFullyTransparentHexColor
  }

  // MARK: - Builtins

  var builtinCPU: CPUBuiltinConfig = .default
  var builtinPrivacySpacer: SpacerBuiltinConfig = .privacyDefault
  var builtinSpacers: [NamedSpacerBuiltinConfig] = []
  var builtinInbox: InboxBuiltinConfig = .default
  var builtinBattery: BatteryBuiltinConfig = .default
  var builtinGroups: [BuiltinGroupConfig] = []
  var builtinSpaces: SpacesBuiltinConfig = .default
  var builtinFrontApp: FrontAppBuiltinConfig = .default
  var builtinAeroSpaceMode: AeroSpaceModeBuiltinConfig = .default
  var builtinVolume: VolumeBuiltinConfig = .default
  var builtinWiFi: WiFiBuiltinConfig = .default
  var builtinCalendar: CalendarBuiltinConfig = .default
  var builtinTime: FormattedBuiltinConfig = .timeDefault
  var builtinDate: FormattedBuiltinConfig = .dateDefault

  // MARK: - Transient config state

  /// Most recent config load failure, when any.
  var loadFailureState: LoadFailureState?
  /// Runtime directories required by parsed config.
  var registeredDirectories: [String: RequiredDirectory] = [:]
  /// Non-fatal warnings produced while parsing the current config.
  var configWarnings: [String] = []

  private init(
    configPathOverride: String? = nil,
    builtInSurfacePolicy: EasyBarBuiltInSurfacePolicy = .all
  ) {
    self.configPathOverride = expandedPath(configPathOverride)
    self.builtInSurfacePolicy = builtInSurfacePolicy

    appSection = .init(
      runtimeDirectory: "",
      widgetsPath: "",
      luaPath: SharedPathDefaults.defaultLuaPath,
      luaSocketPath: "",
      environment: SharedPathDefaults.defaultLuaEnvironment,
      watchConfigFile: true,
      lockDirectory: "",
      widgetEditorStubPath: "",
      develop: false,
      showMenuBarIcon: true,
      luaCommandLimits: .init(
        timeoutSeconds: 5,
        maxOutputBytes: 64 * 1024,
        maxAsyncJobs: 8
      )
    )
    loggingSection = .init(
      enabled: false,
      level: .info,
      directory: ""
    )
    calendarAgentSection = .init(
      enabled: true,
      socketPath: ""
    )
    networkAgentSection = .init(
      enabled: true,
      socketPath: "",
      refreshIntervalSeconds: 0,
      allowUnauthorizedNonSensitiveFields: false
    )
    themeSection = .default
    barSection = .default

    resetDerivedDefaults()
  }

  /// Builds one unloaded config instance for staged parsing work.
  static func makeUnloadedConfig(
    configPathOverride: String? = nil,
    builtInSurfacePolicy: EasyBarBuiltInSurfacePolicy = .all
  ) -> Config {
    Config(
      configPathOverride: configPathOverride,
      builtInSurfacePolicy: builtInSurfacePolicy
    )
  }

  /// Absolute path to the active config file.
  var configPath: String {
    if let configPathOverride {
      return configPathOverride
    }

    if let override = environmentConfigPathOverride() {
      return override
    }

    return SharedPathDefaults.defaultConfigPath().path
  }

  /// Restores all defaults before parsing again.
  func resetToDefaults() {
    resetStaticDefaults()
    resetDerivedDefaults()
  }

  /// Restores theme defaults.
  func resetThemeDefaults() {
    themeSection = .default
  }

  /// Restores bar defaults.
  func resetBarDefaults() {
    barSection = .default
  }

  /// Restores built-in widget defaults.
  func resetBuiltinDefaults() {
    builtinInbox = .default
    builtinPrivacySpacer = .privacyDefault
    builtinSpacers = []
    builtinCPU = .default
    builtinBattery = .default
    builtinGroups = []
    builtinSpaces = .default
    builtinFrontApp = .default
    builtinAeroSpaceMode = .default
    builtinVolume = .default
    builtinWiFi = .default
    builtinCalendar = .default
    builtinTime = .timeDefault
    builtinDate = .dateDefault
  }
}
