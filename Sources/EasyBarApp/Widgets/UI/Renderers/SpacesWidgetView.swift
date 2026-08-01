import SwiftUI

/// Renders all workspaces with their running applications.
struct SpacesWidgetView: View {

  @EnvironmentObject private var aeroSpaceService: AeroSpaceService
  @EnvironmentObject private var configStore: ConfigSnapshotStore

  private var config: Config.SpacesBuiltinConfig {
    configStore.snapshot.builtins.spaces
  }

  /// Renders the native spaces widget.
  @ViewBuilder
  var body: some View {
    if Self.hasVisibleContent(
      showLabel: config.layout.showLabel,
      showIcons: config.layout.showIcons
    ) {
      ScrollView(.horizontal) {
        HStack(spacing: CGFloat(config.layout.spacing)) {
          ForEach(
            Self.visibleSpaces(
              aeroSpaceService.spaces,
              hideEmpty: config.layout.hideEmpty,
              showLabel: config.layout.showLabel,
              showIcons: config.layout.showIcons,
              showOnlyFocusedLabel: config.layout.showOnlyFocusedLabel,
              collapseInactive: config.layout.collapseInactive
            )
          ) { space in
            interactiveSpacePill(for: space)
          }
        }
        .padding(.horizontal, CGFloat(config.layout.marginX))
        .padding(.vertical, CGFloat(config.layout.marginY))
      }
      .scrollIndicators(.hidden)
      .fixedSize(horizontal: true, vertical: false)
    }
  }

  /// Adds workspace activation semantics without swallowing nested app controls.
  @ViewBuilder
  private func interactiveSpacePill(for space: SpaceItem) -> some View {
    let pill = spacePill(for: space)

    if config.layout.clickToFocusSpace {
      pill
        .contentShape(Rectangle())
        .onTapGesture { focusSpaceIfEnabled(space) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Workspace \(space.name)")
        .accessibilityValue(space.isFocused ? "Focused" : "Not focused")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
          focusSpaceIfEnabled(space)
        }
    } else {
      pill
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Workspace \(space.name)")
        .accessibilityValue(space.isFocused ? "Focused" : "Not focused")
    }
  }

  /// Builds one tappable space pill without using Button styling.
  @ViewBuilder
  private func spacePill(for space: SpaceItem) -> some View {
    HStack(spacing: 6) {
      if shouldShowLabel(for: space) {
        Text(space.name)
          .font(
            .system(
              size: CGFloat(config.text.size),
              weight: config.text.resolvedWeight
            )
          )
          .foregroundStyle(spaceTextColor(for: space))
      }

      if shouldShowIcons(for: space) {
        HStack(spacing: CGFloat(config.icons.spacing)) {
          ForEach(visibleApps(for: space)) { app in
            interactiveAppIcon(for: app)
          }

          hiddenAppBadge(for: space)
        }
      }
    }
    .padding(.horizontal, resolvedPaddingX(for: space))
    .padding(.vertical, resolvedPaddingY(for: space))
    .background(spaceBackgroundColor(for: space))
    .overlay {
      RoundedRectangle(cornerRadius: resolvedCornerRadius(for: space))
        .stroke(
          spaceBorderColor(for: space),
          lineWidth: 1
        )
    }
    .clipShape(
      RoundedRectangle(cornerRadius: resolvedCornerRadius(for: space))
    )
    .scaleEffect(space.isFocused ? CGFloat(config.layout.focusedScale) : 1.0)
    .opacity(space.isFocused ? 1.0 : config.layout.inactiveOpacity)
  }

  /// Adds app activation semantics while preserving the workspace gesture surface.
  @ViewBuilder
  private func interactiveAppIcon(for app: SpaceApp) -> some View {
    let isFocused = app.id == aeroSpaceService.focusedAppID
    let icon = AppIconView(
      app: app,
      isFocusedApp: isFocused,
      config: config,
      themeSnapshot: configStore.snapshot
    )

    if config.layout.clickToFocusApp {
      icon
        .contentShape(Rectangle())
        .onTapGesture { focusAppIfEnabled(app) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Focus \(app.name)")
        .accessibilityValue(isFocused ? "Focused" : "Not focused")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
          focusAppIfEnabled(app)
        }
    } else {
      icon
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(app.name)
        .accessibilityValue(isFocused ? "Focused" : "Not focused")
    }
  }

  /// Returns whether the space label should be shown.
  private func shouldShowLabel(for space: SpaceItem) -> Bool {
    guard config.layout.showLabel else { return false }

    if config.layout.showOnlyFocusedLabel {
      return space.isFocused
    }

    return true
  }

  /// Returns whether app icons should be shown for one space.
  private func shouldShowIcons(for space: SpaceItem) -> Bool {
    guard config.layout.showIcons else { return false }
    guard !isCollapsedInactiveSpace(space) else { return false }
    return true
  }

  /// Returns the visible app icons for one space.
  private func visibleApps(for space: SpaceItem) -> [SpaceApp] {
    let limit = max(0, config.layout.maxIcons)
    guard space.apps.count > limit else { return space.apps }
    return Array(space.apps.prefix(limit))
  }

  /// Returns the number of hidden apps for one space.
  private func hiddenAppCount(for space: SpaceItem) -> Int {
    return max(0, space.apps.count - visibleApps(for: space).count)
  }

  /// Returns horizontal pill padding for one space.
  private func resolvedPaddingX(for space: SpaceItem) -> CGFloat {
    guard isCollapsedInactiveSpace(space) else {
      return CGFloat(config.layout.paddingX)
    }

    return CGFloat(config.layout.collapsedPaddingX)
  }

  /// Returns vertical pill padding for one space.
  private func resolvedPaddingY(for space: SpaceItem) -> CGFloat {
    guard isCollapsedInactiveSpace(space) else {
      return CGFloat(config.layout.paddingY)
    }

    return CGFloat(config.layout.collapsedPaddingY)
  }

  /// Returns the corner radius for one space.
  private func resolvedCornerRadius(for space: SpaceItem) -> CGFloat {
    space.isFocused
      ? CGFloat(config.layout.focusedCornerRadius)
      : CGFloat(config.layout.cornerRadius)
  }

  /// Focuses one space when click-to-focus is enabled.
  private func focusSpaceIfEnabled(_ space: SpaceItem) {
    guard config.layout.clickToFocusSpace else { return }
    aeroSpaceService.focusWorkspace(space.name)
  }

  /// Focuses one app when click-to-focus is enabled.
  private func focusAppIfEnabled(_ app: SpaceApp) {
    guard config.layout.clickToFocusApp else { return }
    aeroSpaceService.focusApp(app)
  }

  /// Builds the hidden-app count badge for one space.
  @ViewBuilder
  private func hiddenAppBadge(for space: SpaceItem) -> some View {
    let count = hiddenAppCount(for: space)
    if count > 0 {
      Text("+\(count)")
        .font(
          .system(
            size: max(10, CGFloat(config.text.size) - 1),
            weight: .medium
          )
        )
        .foregroundStyle(spaceTextColor(for: space))
    }
  }

  /// Returns the text color for one space.
  private func spaceTextColor(for space: SpaceItem) -> Color {
    let snapshot = configStore.snapshot
    return space.isFocused
      ? Theme.spaceFocusedText(snapshot: snapshot)
      : Theme.spaceInactiveText(snapshot: snapshot)
  }

  /// Returns the background color for one space.
  private func spaceBackgroundColor(for space: SpaceItem) -> Color {
    let snapshot = configStore.snapshot
    return space.isFocused
      ? Theme.spaceActiveBackground(snapshot: snapshot)
      : Theme.spaceInactiveBackground(snapshot: snapshot)
  }

  /// Returns the border color for one space.
  private func spaceBorderColor(for space: SpaceItem) -> Color {
    let snapshot = configStore.snapshot
    return space.isFocused
      ? Theme.spaceActiveBorder(snapshot: snapshot)
      : Theme.spaceInactiveBorder(snapshot: snapshot)
  }

  /// Returns whether the space uses the collapsed inactive layout.
  private func isCollapsedInactiveSpace(_ space: SpaceItem) -> Bool {
    return config.layout.collapseInactive && !space.isFocused
  }

  /// Returns whether the spaces widget has any enabled visible content.
  static func hasVisibleContent(showLabel: Bool, showIcons: Bool) -> Bool {
    return showLabel || showIcons
  }

  /// Returns the workspace list after applying content, collapse, and empty-space rules.
  static func visibleSpaces(
    _ spaces: [SpaceItem],
    hideEmpty: Bool,
    showLabel: Bool,
    showIcons: Bool,
    showOnlyFocusedLabel: Bool,
    collapseInactive: Bool
  ) -> [SpaceItem] {
    guard hasVisibleContent(showLabel: showLabel, showIcons: showIcons) else {
      return []
    }

    let inactiveSpacesHaveContent: Bool
    if collapseInactive {
      inactiveSpacesHaveContent = showLabel && showIcons && !showOnlyFocusedLabel
    } else {
      inactiveSpacesHaveContent = showIcons || (showLabel && !showOnlyFocusedLabel)
    }

    return spaces.filter { space in
      guard space.isFocused || inactiveSpacesHaveContent else {
        return false
      }

      return !hideEmpty || space.isFocused || !space.apps.isEmpty
    }
  }
}

/// Renders an individual app icon.
private struct AppIconView: View {

  let app: SpaceApp
  let isFocusedApp: Bool

  let config: Config.SpacesBuiltinConfig
  let themeSnapshot: ConfigSnapshot

  /// Returns the app icon size.
  private var resolvedSize: CGFloat {
    isFocusedApp
      ? CGFloat(config.icons.focusedAppSize)
      : CGFloat(config.icons.size)
  }

  /// Returns the app icon border width.
  private var resolvedBorderWidth: CGFloat {
    isFocusedApp
      ? CGFloat(config.icons.focusedAppBorderWidth)
      : CGFloat(config.icons.borderWidth)
  }

  /// Returns the app icon corner radius.
  private var cornerRadius: CGFloat {
    return CGFloat(config.icons.cornerRadius)
  }

  /// Returns the app icon border color.
  private var borderColor: Color {
    return isFocusedApp ? Theme.spaceFocusedAppBorder(snapshot: themeSnapshot) : Color.clear
  }

  /// Renders one app icon slot.
  var body: some View {
    content
      .frame(width: resolvedSize, height: resolvedSize)
      .clipShape(
        RoundedRectangle(cornerRadius: cornerRadius)
      )
      .overlay {
        RoundedRectangle(cornerRadius: cornerRadius)
          .stroke(
            borderColor,
            lineWidth: resolvedBorderWidth
          )
      }
      .animation(.easeOut(duration: 0.06), value: isFocusedApp)
  }

  /// Returns the rendered app icon or fallback initial.
  private var content: some View {
    return iconContent()
  }

  /// Returns the app icon image or the text fallback.
  @ViewBuilder
  private func iconContent() -> some View {
    if let icon = app.icon() {
      Image(nsImage: icon)
        .resizable()
        .interpolation(.high)
    } else {
      Text(String(app.name.prefix(1)).uppercased())
        .font(.system(size: 9, weight: .bold))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.opacity(0.10))
    }
  }
}
