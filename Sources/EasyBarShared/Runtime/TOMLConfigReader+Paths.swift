import SwiftTOMLEdit

extension TOMLConfigReader {
  /// Returns an expanded path value or the fallback when absent.
  public func expandedPath(_ key: String, fallback: String) throws -> String {
    EasyBarShared.expandedPath(try string(key, fallback: fallback)) ?? fallback
  }

  /// Returns an expanded optional path value or the fallback when absent.
  public func optionalExpandedPath(_ key: String, fallback: String? = nil) throws -> String? {
    EasyBarShared.expandedPath(try optionalString(key, fallback: fallback))
  }
}
