import Foundation

/// Stores resolved widget package data.
struct ResolvedWidgetPackage {
  /// The manifest for this resolved widget package.
  let manifest: WidgetPackageManifest
  /// The directory for this resolved widget package.
  let directory: URL
  /// The source for this resolved widget package.
  let source: String
}
