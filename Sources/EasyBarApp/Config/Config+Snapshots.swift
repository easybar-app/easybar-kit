import EasyBarShared

extension Config {
  /// Captures the current config state.
  func snapshot() -> ConfigSnapshot {
    ConfigSnapshot(
      app: .init(
        configPath: configPath,
        runtimeDirectory: appSection.runtimeDirectory,
        widgetsPath: appSection.widgetsPath,
        luaPath: appSection.luaPath,
        luaSocketPath: appSection.luaSocketPath,
        environment: appSection.environment,
        watchConfigFile: appSection.watchConfigFile,
        lockDirectory: appSection.lockDirectory,
        widgetEditorStubPath: appSection.widgetEditorStubPath,
        develop: appSection.develop,
        showMenuBarIcon: appSection.showMenuBarIcon,
        luaCommandLimits: appSection.luaCommandLimits
      ),
      logging: .init(
        enabled: loggingSection.enabled,
        level: loggingSection.level,
        directory: loggingSection.directory
      ),
      calendarAgent: .init(
        enabled: calendarAgentSection.enabled,
        socketPath: calendarAgentSection.socketPath
      ),
      networkAgent: .init(
        enabled: networkAgentSection.enabled,
        socketPath: networkAgentSection.socketPath,
        refreshIntervalSeconds: networkAgentSection.refreshIntervalSeconds,
        allowUnauthorizedNonSensitiveFields:
          networkAgentSection.allowUnauthorizedNonSensitiveFields
      ),
      theme: .init(
        name: themeSection.name,
        themesDir: themeSection.themesDir,
        colors: themeSection.colors
      ),
      bar: barSection,
      builtins: .init(
        inbox: builtinInbox,
        privacySpacer: builtinPrivacySpacer,
        cpu: builtinCPU,
        battery: builtinBattery,
        groups: builtinGroups,
        spaces: builtinSpaces,
        frontApp: builtinFrontApp,
        aerospaceMode: builtinAeroSpaceMode,
        volume: builtinVolume,
        wifi: builtinWiFi,
        calendar: builtinCalendar,
        time: builtinTime,
        date: builtinDate
      )
    )
  }

  /// Restores one previous config snapshot.
  func apply(_ snapshot: ConfigSnapshot) {
    applyAppSnapshot(snapshot)
    applyThemeSnapshot(snapshot)
    applyBarSnapshot(snapshot)
    applyBuiltinSnapshot(snapshot)
  }

  /// Restores the app-level config snapshot.
  func applyAppSnapshot(_ snapshot: ConfigSnapshot) {
    appSection = .init(
      runtimeDirectory: snapshot.app.runtimeDirectory,
      widgetsPath: snapshot.app.widgetsPath,
      luaPath: snapshot.app.luaPath,
      luaSocketPath: snapshot.app.luaSocketPath,
      environment: snapshot.app.environment,
      watchConfigFile: snapshot.app.watchConfigFile,
      lockDirectory: snapshot.app.lockDirectory,
      widgetEditorStubPath: snapshot.app.widgetEditorStubPath,
      develop: snapshot.app.develop,
      showMenuBarIcon: snapshot.app.showMenuBarIcon,
      luaCommandLimits: snapshot.app.luaCommandLimits
    )

    loggingSection = .init(
      enabled: snapshot.logging.enabled,
      level: snapshot.logging.level,
      directory: snapshot.logging.directory
    )

    calendarAgentSection = .init(
      enabled: snapshot.calendarAgent.enabled,
      socketPath: snapshot.calendarAgent.socketPath
    )

    networkAgentSection = .init(
      enabled: snapshot.networkAgent.enabled,
      socketPath: snapshot.networkAgent.socketPath,
      refreshIntervalSeconds: snapshot.networkAgent.refreshIntervalSeconds,
      allowUnauthorizedNonSensitiveFields:
        snapshot.networkAgent.allowUnauthorizedNonSensitiveFields
    )
  }

  /// Restores the theme config snapshot.
  func applyThemeSnapshot(_ snapshot: ConfigSnapshot) {
    themeSection = .init(
      name: snapshot.theme.name,
      themesDir: snapshot.theme.themesDir,
      colors: snapshot.theme.colors
    )
  }

  /// Restores the bar config snapshot.
  func applyBarSnapshot(_ snapshot: ConfigSnapshot) {
    barSection = snapshot.bar
  }

  /// Restores the built-in widget config snapshot.
  func applyBuiltinSnapshot(_ snapshot: ConfigSnapshot) {
    builtinInbox = snapshot.builtins.inbox
    builtinPrivacySpacer = snapshot.builtins.privacySpacer
    builtinCPU = snapshot.builtins.cpu
    builtinBattery = snapshot.builtins.battery
    builtinGroups = snapshot.builtins.groups
    builtinSpaces = snapshot.builtins.spaces
    builtinFrontApp = snapshot.builtins.frontApp
    builtinAeroSpaceMode = snapshot.builtins.aerospaceMode
    builtinVolume = snapshot.builtins.volume
    builtinWiFi = snapshot.builtins.wifi
    builtinCalendar = snapshot.builtins.calendar
    builtinTime = snapshot.builtins.time
    builtinDate = snapshot.builtins.date
  }
}
