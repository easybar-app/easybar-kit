import Foundation
import XCTest

@testable import EasyBarCtl

final class WidgetPackageSearcherTests: XCTestCase {
  func testDefaultRegistrySourceUsesOfficialRepository() {
    XCTAssertEqual(
      WidgetPackageRegistryLoader.defaultSource,
      "https://raw.githubusercontent.com/easybar-app/registry/main/index.json"
    )
  }

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
          "versions": [{
            "version": "1.2.0",
            "archive": "https://example.invalid/tailscale-1.2.0.tar.gz",
            "sha256": "0000000000000000000000000000000000000000000000000000000000000000"
          }]
        },
        {
          "name": "retry-kit",
          "kind": "library",
          "latest": "1.0.0",
          "description": "Retry helpers.",
          "categories": ["library"],
          "versions": [{
            "version": "1.0.0",
            "archive": "https://example.invalid/retry-kit-1.0.0.tar.gz",
            "sha256": "0000000000000000000000000000000000000000000000000000000000000000"
          }]
        },
        {
          "name": "wireguard",
          "kind": "widget",
          "latest": "0.4.0",
          "description": "VPN controls.",
          "categories": ["network"],
          "versions": [{
            "version": "0.4.0",
            "archive": "https://example.invalid/wireguard-0.4.0.tar.gz",
            "sha256": "0000000000000000000000000000000000000000000000000000000000000000"
          }]
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
        "versions": [{
          "version": "1.0.0",
          "archive": "https://example.invalid/duplicate-1.0.0.tar.gz",
          "sha256": "0000000000000000000000000000000000000000000000000000000000000000"
        }]
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
  func testRegistryLoaderRejectsLatestVersionMissingFromReleases() async throws {
    let index = FileManager.default.temporaryDirectory.appending(
      path: "easybar-registry-latest-\(UUID().uuidString).json"
    )
    defer { try? FileManager.default.removeItem(at: index) }
    try """
    {
      "registry_version": 1,
      "packages": [{
        "name": "clock",
        "kind": "widget",
        "latest": "2.0.0",
        "description": "Clock.",
        "categories": [],
        "versions": [{
          "version": "1.0.0",
          "archive": "https://example.invalid/clock-1.0.0.tar.gz",
          "sha256": "0000000000000000000000000000000000000000000000000000000000000000"
        }]
      }]
    }
    """.write(to: index, atomically: true, encoding: .utf8)

    do {
      _ = try await WidgetPackageRegistryLoader().load(source: index.path)
      XCTFail("Expected missing latest release to be rejected")
    } catch let error as WidgetPackageError {
      XCTAssertEqual(
        error,
        .invalidRegistry("package 'clock' latest version is not present in releases")
      )
    }
  }

  func testRegistryLoaderRejectsInvalidReleaseIntegrityMetadata() async throws {
    let index = FileManager.default.temporaryDirectory.appending(
      path: "easybar-registry-integrity-\(UUID().uuidString).json"
    )
    defer { try? FileManager.default.removeItem(at: index) }
    try """
    {
      "registry_version": 1,
      "packages": [{
        "name": "clock",
        "kind": "widget",
        "latest": "1.0.0",
        "description": "Clock.",
        "categories": [],
        "versions": [{
          "version": "1.0.0",
          "archive": "https://example.invalid/clock-1.0.0.tar.gz",
          "sha256": "not-a-digest"
        }]
      }]
    }
    """.write(to: index, atomically: true, encoding: .utf8)

    do {
      _ = try await WidgetPackageRegistryLoader().load(source: index.path)
      XCTFail("Expected invalid SHA-256 to be rejected")
    } catch let error as WidgetPackageError {
      XCTAssertEqual(
        error,
        .invalidRegistry("package 'clock' release '1.0.0' has an invalid SHA-256")
      )
    }
  }

  func testRegistryLoaderRejectsPlaintextHTTP() async {
    do {
      _ = try await WidgetPackageRegistryLoader().load(source: "http://example.invalid/index.json")
      XCTFail("Expected plaintext HTTP registry to be rejected")
    } catch let error as WidgetPackageError {
      XCTAssertEqual(error, .invalidRegistry("unsupported URL scheme 'http'"))
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

}
