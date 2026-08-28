import Foundation
import XCTest

@testable import EasyBarCtl

final class WidgetPackageReloadPlanTests: XCTestCase {
  func testUpdatedWidgetReloadsOnlyItself() throws {
    let packages = [
      package(name: "clock", kind: .widget),
      package(name: "weather", kind: .widget),
    ]

    let plan = try WidgetPackageReloadPlanner.make(
      changedNames: ["clock"],
      packages: packages
    )

    XCTAssertEqual(plan.packages, ["clock"])
    XCTAssertEqual(plan.modules, [])
    XCTAssertEqual(plan.widgets, ["clock"])
  }

  func testUpdatedLibraryReloadsTransitiveDependentsDependencyFirst() throws {
    let packages = [
      package(name: "base", kind: .library, exports: ["base": "base.lua"]),
      package(
        name: "policy",
        kind: .library,
        dependencies: ["base": "^1.0.0"],
        exports: ["policy": "policy.lua"]
      ),
      package(
        name: "brew",
        kind: .widget,
        dependencies: ["policy": "^1.0.0"]
      ),
      package(
        name: "inbox-brew",
        kind: .widget,
        dependencies: ["policy": "^1.0.0"]
      ),
      package(name: "weather", kind: .widget),
    ]

    let plan = try WidgetPackageReloadPlanner.make(
      changedNames: ["base"],
      packages: packages
    )

    XCTAssertEqual(plan.packages, ["base", "policy", "brew", "inbox-brew"])
    XCTAssertEqual(plan.modules, ["base", "policy"])
    XCTAssertEqual(plan.widgets, ["brew", "inbox-brew"])
  }

  func testMultipleUpdatedPackagesProduceOneDeduplicatedReloadPlan() throws {
    let packages = [
      package(name: "base", kind: .library, exports: ["base": "base.lua"]),
      package(
        name: "policy",
        kind: .library,
        dependencies: ["base": "^1.0.0"],
        exports: ["policy": "policy.lua"]
      ),
      package(
        name: "brew",
        kind: .widget,
        dependencies: ["policy": "^1.0.0"]
      ),
    ]

    let plan = try WidgetPackageReloadPlanner.make(
      changedNames: ["base", "policy"],
      packages: packages
    )

    XCTAssertEqual(plan.packages, ["base", "policy", "brew"])
    XCTAssertEqual(plan.modules, ["base", "policy"])
    XCTAssertEqual(plan.widgets, ["brew"])
  }

  func testDependencyCycleIsRejected() {
    let packages = [
      package(
        name: "left",
        kind: .library,
        dependencies: ["right": "^1.0.0"],
        exports: ["left": "left.lua"]
      ),
      package(
        name: "right",
        kind: .library,
        dependencies: ["left": "^1.0.0"],
        exports: ["right": "right.lua"]
      ),
    ]

    XCTAssertThrowsError(
      try WidgetPackageReloadPlanner.make(
        changedNames: ["left"],
        packages: packages
      )
    )
  }

  func testReloadPlanStoreWritesRuntimeContract() throws {
    let directory = FileManager.default.temporaryDirectory.appending(
      path: "easybar-reload-plan-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    defer { try? FileManager.default.removeItem(at: directory) }

    let plan = WidgetPackageReloadPlan(
      packages: ["base", "policy", "brew", "inbox-brew"],
      modules: ["base", "policy"],
      widgets: ["brew", "inbox-brew"]
    )
    let store = WidgetPackageReloadPlanStore()
    try store.write(plan, to: directory)

    let data = try Data(contentsOf: store.url(in: directory))
    XCTAssertEqual(try JSONDecoder().decode(WidgetPackageReloadPlan.self, from: data), plan)
  }

  private func package(
    name: String,
    kind: WidgetPackageKind,
    dependencies: [String: String] = [:],
    exports: [String: String] = [:]
  ) -> InstalledWidgetPackage {
    InstalledWidgetPackage(
      name: name,
      version: "1.0.0",
      kind: kind,
      entrypoint: kind == .widget ? "widget.lua" : nil,
      dependencies: dependencies,
      exports: exports,
      source: "https://example.invalid/\(name)-1.0.0.tar.gz"
    )
  }
}
