import EasyBarShared
import Foundation
import SwiftTOMLEdit
import XCTest

@testable import EasyBarApp

final class NativeBuiltinContextMenuTests: XCTestCase {
  func testVolumeMenuReflectsMuteConfigurationAndCapabilities() throws {
    var config = Config.VolumeBuiltinConfig.default
    config.showPercentage = false
    config.expandToSliderOnHover = true

    let menu = try XCTUnwrap(
      WidgetContextMenuItem.validated(
        VolumeContextMenu.make(
          config: config,
          isMuted: true,
          capabilities: .init(canReadVolume: true, canSetVolume: true, canMute: true)
        )
      )
    )

    XCTAssertEqual(menu.first?.title, "Unmute")
    XCTAssertEqual(menu.first?.enabled, true)
    XCTAssertEqual(
      menu.first(where: { $0.id == VolumeContextMenuAction.toggleShowPercentage.id })?.checked,
      false
    )
    XCTAssertEqual(
      menu.first(where: { $0.id == VolumeContextMenuAction.toggleExpandOnHover.id })?.checked,
      true
    )
  }

  func testVolumeMenuDisablesUnsupportedAudioActions() throws {
    let menu = try XCTUnwrap(
      WidgetContextMenuItem.validated(
        VolumeContextMenu.make(
          config: .default,
          isMuted: false,
          capabilities: .init(canReadVolume: true, canSetVolume: false, canMute: false)
        )
      )
    )

    XCTAssertEqual(
      menu.first(where: { $0.id == VolumeContextMenuAction.toggleMute.id })?.enabled,
      false
    )
    XCTAssertEqual(
      menu.first(where: { $0.id == VolumeContextMenuAction.toggleExpandOnHover.id })?.enabled,
      false
    )
  }

  func testVolumePercentageRemainsVisibleInAlwaysExpandedMode() {
    var config = Config.VolumeBuiltinConfig.default
    config.showPercentage = true
    config.expandToSliderOnHover = false

    XCTAssertEqual(
      VolumePresentation.percentageText(
        normalizedVolume: 0.42,
        config: config,
        isHovered: false,
        canReadVolume: true,
        canSetVolume: true
      ),
      "42%"
    )
  }

  func testVolumeActionsDecodeOnlySupportedValues() {
    XCTAssertEqual(VolumeContextMenuAction(id: VolumeContextMenuAction.toggleMute.id), .toggleMute)
    XCTAssertEqual(
      VolumeContextMenuAction(id: VolumeContextMenuAction.toggleShowPercentage.id),
      .toggleShowPercentage
    )
    XCTAssertEqual(
      VolumeContextMenuAction(id: VolumeContextMenuAction.toggleExpandOnHover.id),
      .toggleExpandOnHover
    )
    XCTAssertEqual(
      VolumeContextMenuAction(id: VolumeContextMenuAction.openSoundSettings.id),
      .openSoundSettings
    )
    XCTAssertNil(VolumeContextMenuAction(id: "volume.unknown"))
  }

  func testCPUMenuReflectsHistoryAndInterval() throws {
    var config = Config.CPUBuiltinConfig.default
    config.historySize = 30
    config.sampleIntervalSeconds = 5

    let menu = try XCTUnwrap(WidgetContextMenuItem.validated(CPUContextMenu.make(config: config)))
    let historyItems = try XCTUnwrap(menu.first(where: { $0.title == "History" })?.submenu)
    let intervalItems = try XCTUnwrap(
      menu.first(where: { $0.title == "Refresh Interval" })?.submenu
    )

    XCTAssertEqual(
      historyItems.first(where: { $0.id == CPUContextMenuAction.setHistorySize(30).id })?.checked,
      true
    )
    XCTAssertEqual(
      intervalItems.first(where: { $0.id == CPUContextMenuAction.setSampleInterval(5).id })?
        .checked,
      true
    )
  }

  func testCPUMenuShowsCheckedCustomValues() throws {
    var config = Config.CPUBuiltinConfig.default
    config.historySize = 20
    config.sampleIntervalSeconds = 3.5

    let menu = try XCTUnwrap(WidgetContextMenuItem.validated(CPUContextMenu.make(config: config)))
    let historyItems = try XCTUnwrap(menu.first(where: { $0.title == "History" })?.submenu)
    let intervalItems = try XCTUnwrap(
      menu.first(where: { $0.title == "Refresh Interval" })?.submenu
    )

    XCTAssertEqual(historyItems.first?.title, "Custom: 20 Samples")
    XCTAssertEqual(historyItems.first?.checked, true)
    XCTAssertEqual(historyItems.first?.enabled, false)
    XCTAssertEqual(intervalItems.first?.title, "Custom: 3.5 Seconds")
    XCTAssertEqual(intervalItems.first?.checked, true)
    XCTAssertEqual(intervalItems.first?.enabled, false)
  }

  func testCPUActionsRejectUnsupportedPresetValues() {
    XCTAssertEqual(
      CPUContextMenuAction(id: CPUContextMenuAction.setHistorySize(60).id),
      .setHistorySize(60)
    )
    XCTAssertEqual(
      CPUContextMenuAction(id: CPUContextMenuAction.setSampleInterval(2).id),
      .setSampleInterval(2)
    )
    XCTAssertEqual(
      CPUContextMenuAction(id: CPUContextMenuAction.resetHistory.id),
      .resetHistory
    )
    XCTAssertEqual(
      CPUContextMenuAction(id: CPUContextMenuAction.openActivityMonitor.id),
      .openActivityMonitor
    )
    XCTAssertNil(CPUContextMenuAction(id: CPUContextMenuAction.customHistoryID))
    XCTAssertNil(CPUContextMenuAction(id: CPUContextMenuAction.customIntervalID))
    XCTAssertNil(CPUContextMenuAction(id: "cpu.history.20"))
    XCTAssertNil(CPUContextMenuAction(id: "cpu.interval.3"))
  }

  func testAeroSpaceModeMenuReflectsLayoutAndKeepsVisibleContent() throws {
    var config = Config.AeroSpaceModeBuiltinConfig.default
    config.showIcon = true
    config.showText = false

    let menu = try XCTUnwrap(
      WidgetContextMenuItem.validated(
        AeroSpaceModeContextMenu.make(config: config, currentLayout: .vAccordion)
      )
    )
    let layoutItems = try XCTUnwrap(menu.first?.submenu)

    XCTAssertEqual(
      layoutItems.first(where: {
        $0.id == AeroSpaceModeContextMenuAction.setLayout(.vAccordion).id
      })?.checked,
      true
    )
    XCTAssertEqual(
      menu.first(where: { $0.id == AeroSpaceModeContextMenuAction.toggleShowIcon.id })?.enabled,
      false
    )
    XCTAssertEqual(
      menu.first(where: { $0.id == AeroSpaceModeContextMenuAction.toggleShowText.id })?.enabled,
      true
    )
  }

  func testAeroSpaceModeActionsRejectUnknownLayout() {
    XCTAssertEqual(
      AeroSpaceModeContextMenuAction(id: AeroSpaceModeContextMenuAction.setLayout(.hTiles).id),
      .setLayout(.hTiles)
    )
    XCTAssertEqual(
      AeroSpaceModeContextMenuAction(id: AeroSpaceModeContextMenuAction.openConfig.id),
      .openConfig
    )
    XCTAssertNil(AeroSpaceModeContextMenuAction(id: "aerospace_mode.layout.unknown"))
    XCTAssertNil(AeroSpaceModeContextMenuAction(id: "aerospace_mode.layout.grid"))
  }

  func testAeroSpaceActionsUseExpectedCLIArguments() {
    XCTAssertEqual(AeroSpaceCommandArguments.layout(.hTiles), ["layout", "h_tiles"])
    XCTAssertEqual(AeroSpaceCommandArguments.layout(.floating), ["layout", "floating"])
    XCTAssertEqual(AeroSpaceCommandArguments.configPath, ["config", "--config-path"])
  }

  func testFrontAppMenuUsesResolvedCapabilitiesAndKeepsVisibleContent() throws {
    var config = Config.FrontAppBuiltinConfig.default
    config.showIcon = false
    config.showName = true

    let menu = try XCTUnwrap(
      WidgetContextMenuItem.validated(
        FrontAppContextMenu.make(
          config: config,
          canHideFocusedApp: false,
          canRevealFocusedApp: false
        )
      )
    )

    XCTAssertEqual(
      menu.first(where: { $0.id == FrontAppContextMenuAction.hideApplication.id })?.enabled,
      false
    )
    XCTAssertEqual(
      menu.first(where: { $0.id == FrontAppContextMenuAction.toggleShowIcon.id })?.enabled,
      true
    )
    XCTAssertEqual(
      menu.first(where: { $0.id == FrontAppContextMenuAction.toggleShowName.id })?.enabled,
      false
    )
    XCTAssertEqual(
      menu.first(where: { $0.id == FrontAppContextMenuAction.revealInFinder.id })?.enabled,
      false
    )
    XCTAssertEqual(
      menu.first(where: { $0.id == FrontAppContextMenuAction.revealInFinder.id })?.title,
      "Show in Finder"
    )
  }

  @MainActor
  func testSnapshotStoreAppliesNewWidgetOverridesIndependently() {
    let original = Config.makeUnloadedConfig().snapshot()
    let store = ConfigSnapshotStore(snapshot: original)

    var cpu = original.builtins.cpu
    cpu.historySize = 60
    store.applyCPUOverride(cpu)
    XCTAssertEqual(store.snapshot.builtins.cpu.historySize, 60)
    XCTAssertEqual(
      store.snapshot.builtins.volume.showPercentage,
      original.builtins.volume.showPercentage
    )

    var volume = original.builtins.volume
    volume.showPercentage = false
    store.applyVolumeOverride(volume)
    XCTAssertEqual(store.snapshot.builtins.volume.showPercentage, false)
    XCTAssertEqual(store.snapshot.builtins.cpu.historySize, 60)

    var frontApp = original.builtins.frontApp
    frontApp.showName = false
    store.applyFrontAppOverride(frontApp)
    XCTAssertEqual(store.snapshot.builtins.frontApp.showName, false)
    XCTAssertEqual(
      store.snapshot.builtins.aerospaceMode.showText,
      original.builtins.aerospaceMode.showText
    )

    var mode = original.builtins.aerospaceMode
    mode.showText = true
    store.applyAeroSpaceModeOverride(mode)
    XCTAssertEqual(store.snapshot.builtins.aerospaceMode.showText, true)
    XCTAssertEqual(store.snapshot.builtins.frontApp.showName, false)
  }

  @MainActor
  func testSnapshotStoreKeepsLiveConfigSynchronizedWithWidgetOverrides() async {
    let config = Config.makeUnloadedConfig()
    let store = ConfigSnapshotStore(
      snapshot: config.snapshot(),
      snapshotDidChange: { config.apply($0) }
    )
    var battery = store.snapshot.builtins.battery
    battery.displayMode = .always

    store.applyBatteryOverride(battery)

    let managerSnapshot = await ConfigManager(config: config).snapshot()
    XCTAssertEqual(managerSnapshot.builtins.battery.displayMode, .always)
  }

  @MainActor
  func testConfigUpdateCommitsRuntimeStateOnlyAfterSuccessfulPersistence() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("easybar-context-menu-success-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let configURL = directory.appendingPathComponent("config.toml")
    try """
    # Keep this comment.
    [builtins.volume.content]
    show_percentage = true # Keep this inline comment.
    """.write(to: configURL, atomically: true, encoding: .utf8)

    let original = Config.makeUnloadedConfig().snapshot()
    let store = ConfigSnapshotStore(snapshot: original)
    var localConfig = original.builtins.volume
    var updated = localConfig
    updated.showPercentage = false

    let persisted = NativeWidgetConfigUpdate.persist(
      edits: [
        TOMLEdit(
          path: ["builtins", "volume", "content", "show_percentage"],
          value: .bool(false)
        )
      ],
      using: ConfigPersistence(configPath: configURL.path, logger: silentLogger())
    ) {
      localConfig = updated
      store.applyVolumeOverride(updated)
    }

    XCTAssertTrue(persisted)
    XCTAssertEqual(localConfig.showPercentage, false)
    XCTAssertEqual(store.snapshot.builtins.volume.showPercentage, false)

    let source = try String(contentsOf: configURL, encoding: .utf8)
    XCTAssertTrue(source.contains("# Keep this comment."))
    XCTAssertTrue(source.contains("show_percentage = false # Keep this inline comment."))
  }

  @MainActor
  func testConfigUpdateLeavesRuntimeStateUnchangedWhenPersistenceFails() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("easybar-context-menu-failure-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let configURL = directory.appendingPathComponent("config.toml")
    try "[invalid".write(to: configURL, atomically: true, encoding: .utf8)

    let original = Config.makeUnloadedConfig().snapshot()
    let store = ConfigSnapshotStore(snapshot: original)
    var localConfig = original.builtins.volume
    var updated = localConfig
    updated.showPercentage.toggle()

    var commitCalled = false
    let persisted = NativeWidgetConfigUpdate.persist(
      edits: [
        TOMLEdit(
          path: ["builtins", "volume", "content", "show_percentage"],
          value: .bool(updated.showPercentage)
        )
      ],
      using: ConfigPersistence(configPath: configURL.path, logger: silentLogger())
    ) {
      commitCalled = true
      localConfig = updated
      store.applyVolumeOverride(updated)
    }

    XCTAssertFalse(persisted)
    XCTAssertFalse(commitCalled)
    XCTAssertEqual(localConfig.showPercentage, original.builtins.volume.showPercentage)
    XCTAssertEqual(
      store.snapshot.builtins.volume.showPercentage,
      original.builtins.volume.showPercentage
    )
  }

  @MainActor
  func testInboxStyleConfigUpdateWritesStateKeysToStyleSection() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("easybar-inbox-style-update-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let configURL = directory.appendingPathComponent("config.toml")
    try """
    [builtins.inbox.content]
    use_inactive_style_when_read = true # Keep behavior here.
    """.write(to: configURL, atomically: true, encoding: .utf8)

    let persisted = NativeWidgetConfigUpdate.persist(
      edits: [
        TOMLEdit(
          path: ["builtins", "inbox", "style", "unread_icon"],
          value: .string("UNREAD")
        ),
        TOMLEdit(
          path: ["builtins", "inbox", "style", "read_icon"],
          value: .string("READ")
        ),
        TOMLEdit(
          path: ["builtins", "inbox", "style", "unread_icon_color"],
          value: .string("theme.text_secondary")
        ),
        TOMLEdit(
          path: ["builtins", "inbox", "style", "read_icon_color"],
          value: .string("theme.muted")
        ),
        TOMLEdit(
          path: ["builtins", "inbox", "style", "unread_count_color"],
          value: .string("theme.accent")
        ),
      ],
      using: ConfigPersistence(configPath: configURL.path, logger: silentLogger())
    ) {}

    XCTAssertTrue(persisted)
    let source = try String(contentsOf: configURL, encoding: .utf8)
    XCTAssertTrue(source.contains("[builtins.inbox.style]"))
    XCTAssertTrue(source.contains("unread_icon = \"UNREAD\""))
    XCTAssertTrue(source.contains("read_icon = \"READ\""))
    XCTAssertTrue(source.contains("unread_icon_color = \"theme.text_secondary\""))
    XCTAssertTrue(source.contains("read_icon_color = \"theme.muted\""))
    XCTAssertTrue(source.contains("unread_count_color = \"theme.accent\""))
    XCTAssertTrue(source.contains("use_inactive_style_when_read = true # Keep behavior here."))
  }

  private func silentLogger() -> ProcessLogger {
    ProcessLogger(
      label: "native-context-menu-tests",
      minimumLevel: .error,
      outputStream: nil,
      errorStream: nil
    )
  }
}
