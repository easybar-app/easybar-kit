import Foundation
import SwiftTOMLEdit

/// Fixed placement used by bar widgets and nodes.
public enum WidgetPosition: String, Codable, CaseIterable, TOMLStringDecodable, Sendable {
  case left
  case center
  case right
}
