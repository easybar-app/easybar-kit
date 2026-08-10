import EasyBarCalendarConfig
import EasyBarShared
import Foundation

typealias CalendarAnchorLayout = EasyBarCalendarConfig.CalendarAnchorLayout
typealias WidgetPosition = EasyBarShared.WidgetPosition

/// Fixed node kinds rendered by SwiftUI.
enum WidgetNodeKind: String, Codable, Sendable {
  case item
  case row
  case column
  case group
  case popup
  case slider
  case progressSlider = "progress_slider"
  case progress
  case sparkline
  case spaces
  case wifiIndicator = "wifi_indicator"

}

/// Internal role markers for special child nodes.
enum WidgetNodeRole: String, Codable, Sendable {
  case popupAnchor = "popup-anchor"
  case popupContent = "popup-content"
}
