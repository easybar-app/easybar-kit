import AppKit
import EasyBarShared

/// Persistent menu-bar controller that remains available while the EasyBar runtime is stopped.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
  private let statusItem: NSStatusItem
  private let menu = NSMenu()
  private let menuFactory: EasyBarMenuFactory

  init(menuFactory: EasyBarMenuFactory) {
    self.menuFactory = menuFactory
    self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    super.init()

    menu.delegate = self
    statusItem.menu = menu
    if let button = statusItem.button {
      button.image = Self.menuBarImage()
      button.toolTip = "EasyBar"
    }
  }

  /// Loads the monochrome EasyBar logo and marks it for native menu-bar tinting.
  private static func menuBarImage() -> NSImage? {
    let image =
      AppResourceLocator.url(
        forResource: "easybar-menubar", withExtension: "svg", subdirectory: "Assets"
      )
      .flatMap(NSImage.init(contentsOf:))
      ?? NSImage(systemSymbolName: "menubar.rectangle", accessibilityDescription: "EasyBar")

    image?.isTemplate = true
    image?.size = NSSize(width: 20, height: 20)
    image?.accessibilityDescription = "EasyBar"
    return image
  }

  func menuWillOpen(_ menu: NSMenu) {
    menu.removeAllItems()
    let builtMenu = menuFactory.makeMenu()
    while let item = builtMenu.items.first {
      builtMenu.removeItem(item)
      menu.addItem(item)
    }
  }

  /// Shows or removes the controller item from the macOS menu bar.
  func setVisible(_ isVisible: Bool) {
    statusItem.isVisible = isVisible
  }
}
