import Foundation

/// Transport-safe description of one native widget context-menu entry.
struct WidgetContextMenuItem: Codable, Equatable, Sendable {
  static let maximumDepth = 8
  static let maximumItemCount = 256
  static let maximumTextBytes = 1024

  let id: String?
  let title: String?
  let separator: Bool
  let enabled: Bool
  let checked: Bool
  let submenu: [WidgetContextMenuItem]?

  init(
    id: String? = nil,
    title: String? = nil,
    separator: Bool = false,
    enabled: Bool = true,
    checked: Bool = false,
    submenu: [WidgetContextMenuItem]? = nil
  ) {
    self.id = id
    self.title = title
    self.separator = separator
    self.enabled = enabled
    self.checked = checked
    self.submenu = submenu
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decodeIfPresent(String.self, forKey: .id)
    title = try container.decodeIfPresent(String.self, forKey: .title)
    separator = try container.decodeIfPresent(Bool.self, forKey: .separator) ?? false
    enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    checked = try container.decodeIfPresent(Bool.self, forKey: .checked) ?? false
    submenu = try container.decodeIfPresent([WidgetContextMenuItem].self, forKey: .submenu)
  }

  /// Returns a bounded, valid menu tree or nil when no selectable structure remains.
  static func validated(_ items: [WidgetContextMenuItem]?) -> [WidgetContextMenuItem]? {
    guard let items else { return nil }
    var count = 0
    var actionIDs: Set<String> = []

    func validate(_ entries: [WidgetContextMenuItem], depth: Int) -> [WidgetContextMenuItem] {
      guard depth <= maximumDepth else { return [] }
      return entries.compactMap { entry in
        count += 1
        guard count <= maximumItemCount else { return nil }
        if entry.separator { return WidgetContextMenuItem(separator: true) }
        guard let title = entry.title, !title.isEmpty,
          title.lengthOfBytes(using: .utf8) <= maximumTextBytes
        else { return nil }

        if let submenu = entry.submenu {
          guard entry.id == nil else { return nil }
          let children = validate(submenu, depth: depth + 1)
          return children.isEmpty ? nil : WidgetContextMenuItem(title: title, submenu: children)
        }

        guard let id = entry.id, !id.isEmpty,
          id.lengthOfBytes(using: .utf8) <= maximumTextBytes,
          actionIDs.insert(id).inserted
        else { return nil }
        return WidgetContextMenuItem(
          id: id,
          title: title,
          enabled: entry.enabled,
          checked: entry.checked
        )
      }
    }

    let validated = validate(items, depth: 1)
    func containsAction(_ entries: [WidgetContextMenuItem]) -> Bool {
      entries.contains { entry in
        entry.id != nil || entry.submenu.map(containsAction) == true
      }
    }
    return containsAction(validated) ? validated : nil
  }
}
