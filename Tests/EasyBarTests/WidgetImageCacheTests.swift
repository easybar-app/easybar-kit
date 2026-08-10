import EasyBarShared
import Foundation
import SwiftUI
import XCTest

@testable import EasyBarKit

final class WidgetImageCacheTests: XCTestCase {
  private static let pixelPNG = Data(
    base64Encoded:
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
  )!
  private static let redSVG = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 8 8">
      <rect width="8" height="8" fill="red"/>
    </svg>
    """
  private static let blueSVG = redSVG.replacingOccurrences(of: "red", with: "blue")

  private func loadedImage(from result: WidgetImageLoadResult) throws -> LoadedWidgetImage {
    guard case .loaded(let image) = result else {
      throw XCTSkip("Expected a decoded test image")
    }
    return image
  }

  @MainActor
  func testLoaderPublishesDecodedCustomImage() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let url = directory.appendingPathComponent("pixel.png")
    try Self.pixelPNG.write(to: url)

    let loader = WidgetImageLoader()
    XCTAssertNil(loader.image(for: .path(url.path)))

    let shouldLogFailure = await loader.load(source: .path(url.path))

    let loaded = try XCTUnwrap(loader.image(for: .path(url.path)))
    XCTAssertFalse(shouldLogFailure)
    XCTAssertEqual(loaded.image.size, CGSize(width: 1, height: 1))
  }

  @MainActor
  func testLoaderReportsDecodeFailureOnlyOncePerPath() async throws {
    let path = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension("png").path
    let loader = WidgetImageLoader()

    let firstShouldLog = await loader.load(source: .path(path))
    let secondShouldLog = await loader.load(source: .path(path))

    XCTAssertTrue(firstShouldLog)
    XCTAssertFalse(secondShouldLog)
    XCTAssertNil(loader.image(for: .path(path)))
  }

  func testUnchangedPathReusesDecodedImage() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let path = directory.appendingPathComponent("image.png").path
    try Self.pixelPNG.write(to: URL(fileURLWithPath: path))
    let cache = WidgetImageCache()
    let first = try loadedImage(from: await cache.image(for: .path(path)))
    let second = try loadedImage(from: await cache.image(for: .path(path)))

    XCTAssertTrue(first === second)
  }

  func testApplicationBundlePathLoadsWorkspaceIcon() async throws {
    let path = "/System/Library/CoreServices/Finder.app"
    guard FileManager.default.fileExists(atPath: path) else {
      throw XCTSkip("Finder application bundle is unavailable")
    }

    let image = try loadedImage(from: await WidgetImageCache().image(for: .path(path)))

    XCTAssertNotEqual(image.image.size, .zero)
  }

  func testLeastRecentlyUsedImageIsEvictedAtCapacity() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let firstPath = directory.appendingPathComponent("first.png").path
    let secondPath = directory.appendingPathComponent("second.png").path
    let thirdPath = directory.appendingPathComponent("third.png").path
    try Self.pixelPNG.write(to: URL(fileURLWithPath: firstPath))
    try Self.pixelPNG.write(to: URL(fileURLWithPath: secondPath))
    try Self.pixelPNG.write(to: URL(fileURLWithPath: thirdPath))
    let cache = WidgetImageCache(capacity: 2)

    let first = try loadedImage(from: await cache.image(for: .path(firstPath)))
    let second = try loadedImage(from: await cache.image(for: .path(secondPath)))
    _ = await cache.image(for: .path(firstPath))
    _ = await cache.image(for: .path(thirdPath))
    let reloadedFirst = try loadedImage(from: await cache.image(for: .path(firstPath)))
    let reloadedSecond = try loadedImage(from: await cache.image(for: .path(secondPath)))

    XCTAssertTrue(first === reloadedFirst)
    XCTAssertFalse(second === reloadedSecond)
  }

  func testChangedModificationDateReloadsSamePath() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let url = directory.appendingPathComponent("changing.png")
    try Self.pixelPNG.write(to: url)
    let cache = WidgetImageCache()
    let first = try loadedImage(from: await cache.image(for: .path(url.path)))

    try FileManager.default.setAttributes(
      [.modificationDate: Date(timeIntervalSinceNow: 10)],
      ofItemAtPath: url.path
    )
    let second = try loadedImage(from: await cache.image(for: .path(url.path)))

    XCTAssertFalse(first === second)
  }

  func testImageRevisionChangesWhenFileSizeChanges() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let url = directory.appendingPathComponent("changing.png")
    try Self.pixelPNG.write(to: url)
    let first = WidgetImageRevision(source: .path(url.path))

    var enlarged = Self.pixelPNG
    enlarged.append(0)
    try enlarged.write(to: url)
    let second = WidgetImageRevision(source: .path(url.path))

    XCTAssertNotEqual(first, second)
  }

  func testValidInlineSVGDecodesAndReusesCachedImage() async throws {
    let cache = WidgetImageCache()
    let source = WidgetImageSource.svg(Self.redSVG)

    let first = try loadedImage(from: await cache.image(for: source))
    let second = try loadedImage(from: await cache.image(for: source))

    XCTAssertNotEqual(first.image.size, .zero)
    XCTAssertTrue(first === second)
  }

  func testInvalidInlineSVGFailsCleanly() async {
    let cache = WidgetImageCache()

    guard case .failed(let source) = await cache.image(for: .svg("not svg")) else {
      XCTFail("Expected inline SVG decoding to fail")
      return
    }

    XCTAssertEqual(source, .svg("not svg"))
  }

  func testChangedInlineSVGContentCausesReload() async throws {
    let cache = WidgetImageCache()
    let first = try loadedImage(from: await cache.image(for: .svg(Self.redSVG)))
    let second = try loadedImage(from: await cache.image(for: .svg(Self.blueSVG)))

    XCTAssertFalse(first === second)
  }

  @MainActor
  func testPathAndInlineSVGUseTheSameTintingBehavior() {
    let tint = Color.white
    XCTAssertTrue(WidgetImageView.usesTemplateRendering(source: .path("/tmp/icon.png"), tint: tint))
    XCTAssertTrue(WidgetImageView.usesTemplateRendering(source: .svg(Self.redSVG), tint: tint))
    XCTAssertFalse(WidgetImageView.usesTemplateRendering(source: .path("/tmp/icon.png"), tint: nil))
    XCTAssertFalse(WidgetImageView.usesTemplateRendering(source: .svg(Self.redSVG), tint: nil))
    XCTAssertFalse(
      WidgetImageView.usesTemplateRendering(source: .path("/Applications/App.app"), tint: tint)
    )
  }

  func testApplicationBundleIconsKeepOriginalRendering() {
    XCTAssertFalse(WidgetImageSource.path("/Applications/Example.app").allowsTemplateTint)
    XCTAssertFalse(WidgetImageSource.path("/Applications/Example.APP").allowsTemplateTint)
    XCTAssertTrue(WidgetImageSource.path("/tmp/icon.png").allowsTemplateTint)
    XCTAssertTrue(WidgetImageSource.svg(Self.redSVG).allowsTemplateTint)
  }

}
