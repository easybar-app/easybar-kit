import Foundation
import XCTest

@testable import EasyBarCtl

final class WidgetPackageSearcherTests: XCTestCase {
  func testSearchMatchesMetadataAndSortsResults() async throws {
    let index = FileManager.default.temporaryDirectory.appending(
      path: "easybar-registry-search-\(UUID().uuidString).json"
    )
    defer { try? FileManager.default.removeItem(at: index) }
    try """
    {
      "registry_version": 1,
      "packages": [
        {
          "name": "tailscale",
          "kind": "widget",
          "latest": "1.2.0",
          "description": "Tailscale network controls.",
          "categories": ["network", "system"],
          "versions": []
        },
        {
          "name": "retry-kit",
          "kind": "library",
          "latest": "1.0.0",
          "description": "Retry helpers.",
          "categories": ["library"],
          "versions": []
        },
        {
          "name": "wireguard",
          "kind": "widget",
          "latest": "0.4.0",
          "description": "VPN controls.",
          "categories": ["network"],
          "versions": []
        }
      ]
    }
    """.write(to: index, atomically: true, encoding: .utf8)

    let searcher = WidgetPackageSearcher()
    let all = try await searcher.search(query: nil, registrySource: index.path)
    let network = try await searcher.search(query: "NETWORK", registrySource: index.path)
    let libraries = try await searcher.search(query: "library", registrySource: index.path)
    let vpn = try await searcher.search(query: "vpn", registrySource: index.path)
    XCTAssertEqual(all.map(\.name), ["retry-kit", "tailscale", "wireguard"])
    XCTAssertEqual(network.map(\.name), ["tailscale", "wireguard"])
    XCTAssertEqual(libraries.map(\.name), ["retry-kit"])
    XCTAssertEqual(vpn.map(\.name), ["wireguard"])
  }

  func testRegistryLoaderRejectsDuplicatePackageNames() async throws {
    let index = FileManager.default.temporaryDirectory.appending(
      path: "easybar-registry-duplicates-\(UUID().uuidString).json"
    )
    defer { try? FileManager.default.removeItem(at: index) }
    let package = """
      {
        "name": "duplicate",
        "kind": "widget",
        "latest": "1.0.0",
        "description": "Duplicate.",
        "categories": [],
        "versions": []
      }
      """
    try """
    {"registry_version": 1, "packages": [\(package), \(package)]}
    """.write(to: index, atomically: true, encoding: .utf8)

    do {
      _ = try await WidgetPackageRegistryLoader().load(source: index.path)
      XCTFail("Expected duplicate package names to be rejected")
    } catch let error as WidgetPackageError {
      XCTAssertEqual(
        error,
        .invalidRegistry("registry contains duplicate package names")
      )
    }
  }
}
