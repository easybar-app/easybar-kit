import EasyBarShared
import SwiftUI

/// Recursive SwiftUI renderer for one widget node.
struct WidgetNodeView: View {
  let node: WidgetNodeState
  let logger: ProcessLogger

  @EnvironmentObject var store: WidgetStore
  @EnvironmentObject var configStore: ConfigSnapshotStore
  @Environment(\.appViewServices) var appViewServices

  @StateObject var popupPanel = WidgetPopupPanelController()
  @State var popupPresented = false
  @State var anchorHovered = false
  @State var popupHovered = false
  @State var popupCloseTask: Task<Void, Never>?

  var body: some View {
    Group {
      if node.visible {
        renderedNodeView
      } else {
        EmptyView()
      }
    }
    .onChange(of: popupPresented, initial: true) { _, presented in
      updatePopupPanel(isPresented: presented || node.presentsPopupAutomatically)
    }
    .onChange(of: node, initial: false) { _, _ in
      cancelPopupCloseCheck()
      updatePopupPanel(isPresented: popupPresented || node.presentsPopupAutomatically)
    }
    .onDisappear {
      cancelPopupCloseCheck()
      popupPanel.close()
    }
  }
}
