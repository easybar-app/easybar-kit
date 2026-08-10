import Foundation
import XCTest

@testable import EasyBarKit

final class AppResourceLocatorTests: XCTestCase {
  private struct SourceResourceFixture {
    let sourcePath: String
    let resource: String
    let fileExtension: String
    let subdirectory: String?
  }

  func testFindsLuaRuntimeFromSourceTree() throws {
    let url = try XCTUnwrap(
      AppResourceLocator.url(forResource: "runtime", withExtension: "lua")
    )

    XCTAssertTrue(url.path.hasSuffix("Sources/EasyBarKit/Lua/runtime.lua"))
  }

  func testPackagedSourceResourceFixturesExistAndResolve() throws {
    let fixtures = [
      SourceResourceFixture(
        sourcePath: "Sources/EasyBarKit/Lua/runtime.lua",
        resource: "runtime",
        fileExtension: "lua",
        subdirectory: nil
      ),
      SourceResourceFixture(
        sourcePath: "Sources/EasyBarKit/Lua/easybar_api.lua",
        resource: "easybar_api",
        fileExtension: "lua",
        subdirectory: nil
      ),
      SourceResourceFixture(
        sourcePath: "Sources/EasyBarKit/Lua/easybar/json.lua",
        resource: "json",
        fileExtension: "lua",
        subdirectory: "easybar"
      ),
      SourceResourceFixture(
        sourcePath: "Sources/EasyBarKit/Assets/easybar-menubar.svg",
        resource: "easybar-menubar",
        fileExtension: "svg",
        subdirectory: "Assets"
      ),
      SourceResourceFixture(
        sourcePath: "Sources/EasyBarKit/Events/event_catalog.json",
        resource: "event_catalog",
        fileExtension: "json",
        subdirectory: nil
      ),
      SourceResourceFixture(
        sourcePath: "Sources/EasyBarKit/Theme/theme_tokens.json",
        resource: "theme_tokens",
        fileExtension: "json",
        subdirectory: "ThemeTokens"
      ),
    ]

    let repositoryRootURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()

    for fixture in fixtures {
      let sourceURL = repositoryRootURL.appendingPathComponent(fixture.sourcePath)
      XCTAssertTrue(
        FileManager.default.fileExists(atPath: sourceURL.path),
        "Expected source fixture at \(sourceURL.path)"
      )

      let resolvedURL = try XCTUnwrap(
        AppResourceLocator.url(
          forResource: fixture.resource,
          withExtension: fixture.fileExtension,
          subdirectory: fixture.subdirectory
        ),
        "Expected \(fixture.resource).\(fixture.fileExtension) to resolve"
      )
      XCTAssertEqual(resolvedURL.standardizedFileURL, sourceURL.standardizedFileURL)
    }
  }

  func testEventCatalogCandidatesIncludePackagedAndSourceLayouts() {
    let paths = AppResourceLocator.resourceCandidates(
      forResource: "event_catalog",
      withExtension: "json",
      subdirectory: nil
    ).map(\.path)

    XCTAssertTrue(
      paths.contains { $0.hasSuffix("Resources/EasyBar/Events/event_catalog.json") },
      "Expected packaged event catalog candidate in \(paths)"
    )
    XCTAssertTrue(
      paths.contains { $0.hasSuffix("Sources/EasyBarKit/Events/event_catalog.json") },
      "Expected source event catalog candidate in \(paths)"
    )
  }

  func testThemeTokenCandidatesMapLogicalSubdirectoryPerLayout() {
    let paths = AppResourceLocator.resourceCandidates(
      forResource: "theme_tokens",
      withExtension: "json",
      subdirectory: "ThemeTokens"
    ).map(\.path)

    XCTAssertTrue(
      paths.contains { $0.hasSuffix("Resources/EasyBar/ThemeTokens/theme_tokens.json") },
      "Expected packaged theme-token candidate in \(paths)"
    )
    XCTAssertTrue(
      paths.contains { $0.hasSuffix("Sources/EasyBarKit/Theme/theme_tokens.json") },
      "Expected source theme-token candidate in \(paths)"
    )
  }

  func testAssetCandidatesUseAssetsDirectory() {
    let paths = AppResourceLocator.resourceCandidates(
      forResource: "easybar-menubar",
      withExtension: "svg",
      subdirectory: "Assets"
    ).map(\.path)

    XCTAssertTrue(
      paths.contains { $0.hasSuffix("Resources/EasyBar/Assets/easybar-menubar.svg") },
      "Expected packaged asset candidate in \(paths)"
    )
    XCTAssertTrue(
      paths.contains { $0.hasSuffix("Sources/EasyBarKit/Assets/easybar-menubar.svg") },
      "Expected source asset candidate in \(paths)"
    )
  }

  func testLuaSubdirectoryCandidatesStayUnderLuaTree() {
    let paths = AppResourceLocator.resourceCandidates(
      forResource: "json",
      withExtension: "lua",
      subdirectory: "easybar"
    ).map(\.path)

    XCTAssertTrue(
      paths.contains { $0.hasSuffix("Resources/EasyBar/Lua/easybar/json.lua") },
      "Expected packaged Lua subdirectory candidate in \(paths)"
    )
    XCTAssertTrue(
      paths.contains { $0.hasSuffix("Sources/EasyBarKit/Lua/easybar/json.lua") },
      "Expected source Lua subdirectory candidate in \(paths)"
    )
  }
}
