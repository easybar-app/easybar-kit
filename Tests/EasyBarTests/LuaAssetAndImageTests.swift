import EasyBarShared
import Foundation
import XCTest

@testable import EasyBarApp

final class LuaAssetAndImageTests: LuaRenderRuntimeTestCase, @unchecked Sendable {
  func testAssetResolvesSiblingNestedAndNormalizedPaths() async throws {
    let widgets = try makeWidgetsDirectory()
    let node = try await render(
      """
      local item = easybar.add("item", "asset", {
        label = table.concat({
          easybar.asset("github.svg"),
          easybar.asset("assets/icons/warning.svg"),
          easybar.asset("assets/../normalized.svg"),
        }, "|")
      })
      """,
      as: "widget.lua",
      in: widgets
    )

    XCTAssertEqual(
      node.text,
      [
        widgets.appendingPathComponent("github.svg").path,
        widgets.appendingPathComponent("assets/icons/warning.svg").path,
        widgets.appendingPathComponent("normalized.svg").path,
      ].joined(separator: "|")
    )
  }

  func testAssetUsesNestedWidgetSourceDirectory() async throws {
    let widgets = try makeWidgetsDirectory()
    let nested = widgets.appendingPathComponent("github", isDirectory: true)
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

    let node = try await render(
      "easybar.add(\"item\", \"asset\", { label = easybar.asset(\"github.svg\") })",
      as: "github/widget.lua",
      in: widgets
    )

    XCTAssertEqual(node.text, nested.appendingPathComponent("github.svg").path)
  }

  func testAssetCanResolveFromWidgetsRoot() async throws {
    let widgets = try makeWidgetsDirectory()
    let nested = widgets.appendingPathComponent("github", isDirectory: true)
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

    let node = try await render(
      "easybar.add(\"item\", \"asset\", { label = easybar.asset(\"@/assets/github.svg\") })",
      as: "github/widget.lua",
      in: widgets
    )

    XCTAssertEqual(node.text, widgets.appendingPathComponent("assets/github.svg").path)
  }

  func testAssetRejectsInvalidPaths() async throws {
    let widgets = try makeWidgetsDirectory()
    let node = try await render(
      """
      local values = {}
      for _, path in ipairs({ "", "/tmp/icon.svg", "../icon.svg", "nested/../../icon.svg", "@/", "@/../icon.svg" }) do
        local ok = pcall(easybar.asset, path)
        values[#values + 1] = tostring(ok)
      end
      easybar.add("item", "asset", { label = table.concat(values, ",") })
      """,
      as: "widget.lua",
      in: widgets
    )

    XCTAssertEqual(node.text, "false,false,false,false,false,false")
  }

  func testWidgetAPIsKeepIndependentAssetDirectories() async throws {
    let widgets = try makeWidgetsDirectory()
    let firstDirectory = widgets.appendingPathComponent("first", isDirectory: true)
    let secondDirectory = widgets.appendingPathComponent("second", isDirectory: true)
    try FileManager.default.createDirectory(at: firstDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: secondDirectory, withIntermediateDirectories: true)

    let first = try await render(
      "easybar.add(\"item\", \"first\", { label = easybar.asset(\"icon.svg\") })",
      as: "first/widget.lua",
      in: widgets
    )
    let second = try await render(
      "easybar.add(\"item\", \"second\", { label = easybar.asset(\"icon.svg\") })",
      as: "second/widget.lua",
      in: widgets
    )

    XCTAssertEqual(first.text, firstDirectory.appendingPathComponent("icon.svg").path)
    XCTAssertEqual(second.text, secondDirectory.appendingPathComponent("icon.svg").path)
  }

  func testAssetPathAndInlineSVGReachSwiftRenderer() async throws {
    let widgets = try makeWidgetsDirectory()
    let svg = """
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 4 4">
        <path d="M0 0h4v4H0z"/>
      </svg>
      """

    let pathNode = try await render(
      """
      easybar.add("item", "path", {
        icon = { image = { path = easybar.asset("test.svg"), size = 16 } }
      })
      """,
      as: "path.lua",
      in: widgets
    )
    let svgNode = try await render(
      """
      easybar.add("item", "svg", {
        icon = { image = { svg = [=[\(svg)]=], size = 16 } }
      })
      """,
      as: "inline.lua",
      in: widgets
    )

    let expectedPath = widgets.appendingPathComponent("test.svg").path
    XCTAssertEqual(pathNode.imagePath, expectedPath)
    XCTAssertEqual(pathNode.imageSource, .path(expectedPath))
    XCTAssertNil(pathNode.imageSvg)
    XCTAssertEqual(svgNode.imageSvg, svg)
    XCTAssertEqual(svgNode.imageSource, .svg(svg))
    XCTAssertNil(svgNode.imagePath)
    XCTAssertEqual(pathNode.imageSize, 16)
    XCTAssertEqual(svgNode.imageSize, 16)
  }

  func testMissingAndConflictingImageSourcesRenderNoSource() async throws {
    let widgets = try makeWidgetsDirectory()
    let missing = try await render(
      "easybar.add(\"item\", \"missing\", { icon = { image = { size = 16 } } })",
      as: "missing.lua",
      in: widgets
    )
    let conflicting = try await render(
      """
      easybar.add("item", "conflicting", {
        icon = { image = { path = "/tmp/icon.svg", svg = "<svg/>" } }
      })
      """,
      as: "conflicting.lua",
      in: widgets
    )
    let empty = try await render(
      "easybar.add(\"item\", \"empty\", { icon = { image = { svg = \"\" } } })",
      as: "empty.lua",
      in: widgets
    )
    let oversized = try await render(
      "easybar.add(\"item\", \"oversized\", { icon = { image = { svg = string.rep(\"x\", 262145) } } })",
      as: "oversized.lua",
      in: widgets
    )

    XCTAssertNil(missing.imageSource)
    XCTAssertNil(conflicting.imageSource)
    XCTAssertNil(empty.imageSource)
    XCTAssertNil(oversized.imageSource)
  }

  private func render(
    _ source: String,
    as widgetFile: String,
    in widgetsDirectoryURL: URL
  ) async throws -> WidgetNodeState {
    let widgetURL = widgetsDirectoryURL.appendingPathComponent(widgetFile)
    try FileManager.default.createDirectory(
      at: widgetURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try source.write(to: widgetURL, atomically: true, encoding: .utf8)

    let logger = ProcessLogger(label: "lua.asset-image.test", minimumLevel: .error)
    let controller = LuaProcessController(logger: logger)
    let runtimePath = try XCTUnwrap(controller.resolvedRuntimePath())
    let recorder = RuntimeUpdateRecorder()
    let runtime = try RuntimeProcess(
      runtimePath: runtimePath,
      widgetsDirectoryURL: widgetsDirectoryURL,
      recorder: recorder,
      decoder: decoder,
      environment: try luaRuntimeEnvironment(for: widgetsDirectoryURL),
      autoRespondToCommands: true
    )
    defer { runtime.stop() }

    let update = try await nextTreeUpdate(from: recorder) { update in
      update.treePayload?.nodes.contains(where: { $0.id == widgetFileRootID(source) }) == true
    }
    return try XCTUnwrap(
      update.treePayload?.nodes.first(where: { $0.id == widgetFileRootID(source) }))
  }
}

private func widgetFileRootID(_ source: String) -> String {
  let marker = "easybar.add(\"item\", \""
  guard let start = source.range(of: marker)?.upperBound,
    let end = source[start...].firstIndex(of: "\"")
  else {
    return "asset"
  }
  return String(source[start..<end])
}
