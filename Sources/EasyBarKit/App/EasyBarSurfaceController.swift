import AppKit
import EasyBarShared

/// Frontend contract used to present EasyBarKit widgets.
///
/// `easybar` implements this with one custom top-edge panel. `easybar-native`
/// implements it with one `NSStatusItem` per top-level widget.
@MainActor
public protocol EasyBarSurfaceController: AnyObject {
  /// Makes the frontend visible.
  func present()
  /// Hides the frontend without tearing down the shared runtime.
  func hide()
  /// Reapplies frontend layout after configuration changes.
  func reloadLayout()
  /// Releases frontend-owned UI resources during final shutdown.
  func stop()
}

extension EasyBarSurfaceController {
  public func stop() {
    hide()
  }
}

/// Shared inputs supplied to one EasyBar frontend.
@MainActor
public struct EasyBarSurfaceContext {
  public let logger: ProcessLogger
  public let presentationModel: EasyBarPresentationModel

  private let barContextMenuBuilder: (Bool) -> NSMenu

  init(
    logger: ProcessLogger,
    presentationModel: EasyBarPresentationModel,
    barContextMenuBuilder: @escaping (Bool) -> NSMenu
  ) {
    self.logger = logger
    self.presentationModel = presentationModel
    self.barContextMenuBuilder = barContextMenuBuilder
  }

  /// Builds the shared EasyBar context menu.
  public func makeBarContextMenu(showDeveloperSection: Bool = false) -> NSMenu {
    barContextMenuBuilder(showDeveloperSection)
  }
}

/// Factory used by the shared application shell to construct its frontend.
public typealias EasyBarSurfaceFactory =
  @MainActor (EasyBarSurfaceContext) -> any EasyBarSurfaceController
