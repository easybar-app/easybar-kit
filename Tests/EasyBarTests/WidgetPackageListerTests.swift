import EasyBarShared
import Foundation
import XCTest

@testable import EasyBarCtl

final class WidgetPackageListerTests: XCTestCase {
  private var directory: URL!

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory.appending(
      path: "easybar-package-list-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
    directory = nil
  }

  func testListsWidgetsBeforeLibrariesFiltersByKindAndIncludesPins() throws {
    let shared = package(name: "shared", version: "0.1.0", kind: .library)
    let github = package(name: "inbox-github", version: "0.3.0", kind: .widget)
    let brew = package(name: "brew", version: "0.2.0", kind: .widget)
    try WidgetPackageDatabaseStore().write(
      InstalledWidgetPackages(
        layoutVersion: WidgetPackageStore.layoutVersion,
        packages: [shared, github, brew]
      ),
      to: directory
    )
    try WidgetPackagePinStore().write(["inbox-github"], to: directory)

    let lister = WidgetPackageLister(packagesDirectory: directory)
    XCTAssertEqual(
      try lister.installed(filter: .all),
      [status(brew), status(github, pinned: true), status(shared)]
    )
    XCTAssertEqual(
      try lister.installed(filter: .widgets),
      [status(brew), status(github, pinned: true)]
    )
    XCTAssertEqual(try lister.installed(filter: .libraries), [status(shared)])
  }

  func testMissingDatabaseReturnsAnEmptyList() throws {
    XCTAssertEqual(
      try WidgetPackageLister(packagesDirectory: directory).installed(filter: .all),
      []
    )
  }

  func testHumanOutputAlignsNamesVersionsKindsAndPins() {
    let packages = [
      status(package(name: "brew", version: "0.2.0", kind: .widget), pinned: true),
      status(package(name: "shared", version: "0.1.0", kind: .library)),
    ]

    XCTAssertEqual(
      CLIOutput.installedWidgetPackagesText(packages),
      """
      NAME    VERSION  KIND     PINNED
      brew    0.2.0    widget   yes
      shared  0.1.0    library  no
      """
    )
    XCTAssertEqual(CLIOutput.installedWidgetPackagesText([]), "No packages installed.")
  }

  private func status(
    _ package: InstalledWidgetPackage,
    pinned: Bool = false
  ) -> InstalledWidgetPackageStatus {
    InstalledWidgetPackageStatus(package: package, pinned: pinned)
  }

  private func package(
    name: String,
    version: String,
    kind: WidgetPackageKind
  ) -> InstalledWidgetPackage {
    InstalledWidgetPackage(
      name: name,
      version: version,
      kind: kind,
      entrypoint: kind == .widget ? "widget.lua" : nil,
      dependencies: [:],
      exports: [:],
      source: "https://example.com/\(name)-\(version).tar.gz"
    )
  }
}
