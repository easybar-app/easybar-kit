import EasyBarShared
import Foundation
import XCTest

@testable import EasyBarCtl

final class WidgetPackageRegistryLoaderTests: XCTestCase {
  private var directory: URL!
  private var session: URLSession!

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory.appending(
      path: "easybar-registry-loader-tests-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    RegistryURLProtocol.reset()
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [RegistryURLProtocol.self]
    session = URLSession(configuration: configuration)
  }

  override func tearDownWithError() throws {
    session.invalidateAndCancel()
    session = nil
    RegistryURLProtocol.reset()
    try? FileManager.default.removeItem(at: directory)
    directory = nil
  }

  func testRemoteRegistryRevalidatesAndReusesPersistentCache() async throws {
    let source = "https://registry.example.test/index.json"
    let modified = "Fri, 14 Aug 2026 08:00:00 GMT"
    RegistryURLProtocol.enqueue(
      .init(
        statusCode: 200,
        headers: ["ETag": "\"registry-v1\"", "Last-Modified": modified],
        data: registryData(version: "1.0.0")
      )
    )
    RegistryURLProtocol.enqueue(.init(statusCode: 304, headers: [:], data: Data()))

    let firstLoader = WidgetPackageRegistryLoader(
      session: session,
      cacheDirectory: directory
    )
    let first = try await firstLoader.load(source: source)
    XCTAssertEqual(first.packages.first?.latest, "1.0.0")

    let secondLoader = WidgetPackageRegistryLoader(
      session: session,
      cacheDirectory: directory
    )
    let second = try await secondLoader.load(source: source)
    XCTAssertEqual(second.packages.first?.latest, "1.0.0")

    let requests = RegistryURLProtocol.requests()
    XCTAssertEqual(requests.count, 2)
    XCTAssertNil(requests[0].ifNoneMatch)
    XCTAssertNil(requests[0].ifModifiedSince)
    XCTAssertEqual(requests[0].cacheControl, "no-cache")
    XCTAssertEqual(requests[0].cachePolicy, .reloadIgnoringLocalCacheData)
    XCTAssertEqual(requests[1].ifNoneMatch, "\"registry-v1\"")
    XCTAssertEqual(requests[1].ifModifiedSince, modified)
    XCTAssertEqual(requests[1].cacheControl, "no-cache")
    XCTAssertEqual(requests[1].cachePolicy, .reloadIgnoringLocalCacheData)

    let cachedFiles = try FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: nil
    )
    XCTAssertEqual(cachedFiles.filter { $0.pathExtension == "json" }.count, 2)
  }

  func testRefreshBypassesValidatorsAndReplacesPersistentCache() async throws {
    let source = "https://registry.example.test/index.json"
    RegistryURLProtocol.enqueue(
      .init(
        statusCode: 200,
        headers: ["ETag": "\"registry-v1\""],
        data: registryData(version: "1.0.0")
      )
    )
    RegistryURLProtocol.enqueue(
      .init(
        statusCode: 200,
        headers: ["ETag": "\"registry-v2\""],
        data: registryData(version: "1.1.0")
      )
    )
    RegistryURLProtocol.enqueue(.init(statusCode: 304, headers: [:], data: Data()))

    let loader = WidgetPackageRegistryLoader(session: session, cacheDirectory: directory)
    let initial = try await loader.load(source: source)
    XCTAssertEqual(initial.packages.first?.latest, "1.0.0")

    let refreshed = try await loader.load(source: source, refresh: true)
    XCTAssertEqual(refreshed.packages.first?.latest, "1.1.0")

    let recreatedLoader = WidgetPackageRegistryLoader(session: session, cacheDirectory: directory)
    let cached = try await recreatedLoader.load(source: source)
    XCTAssertEqual(cached.packages.first?.latest, "1.1.0")

    let requests = RegistryURLProtocol.requests()
    XCTAssertEqual(requests.count, 3)
    XCTAssertNil(requests[0].ifNoneMatch)
    XCTAssertNil(requests[1].ifNoneMatch)
    XCTAssertNil(requests[1].ifModifiedSince)
    XCTAssertEqual(requests[1].cacheControl, "no-cache")
    XCTAssertEqual(requests[1].cachePolicy, .reloadIgnoringLocalCacheData)
    XCTAssertEqual(requests[2].ifNoneMatch, "\"registry-v2\"")
  }

  func testRemoteRegistryReplacesCacheWhenValidatorChanges() async throws {
    let source = "https://registry.example.test/index.json"
    RegistryURLProtocol.enqueue(
      .init(
        statusCode: 200,
        headers: ["ETag": "\"registry-v1\""],
        data: registryData(version: "1.0.0")
      )
    )
    RegistryURLProtocol.enqueue(
      .init(
        statusCode: 200,
        headers: ["ETag": "\"registry-v2\""],
        data: registryData(version: "1.1.0")
      )
    )
    RegistryURLProtocol.enqueue(.init(statusCode: 304, headers: [:], data: Data()))

    let loader = WidgetPackageRegistryLoader(session: session, cacheDirectory: directory)
    let first = try await loader.load(source: source)
    XCTAssertEqual(first.packages.first?.latest, "1.0.0")

    let second = try await loader.load(source: source)
    XCTAssertEqual(second.packages.first?.latest, "1.1.0")

    let recreatedLoader = WidgetPackageRegistryLoader(session: session, cacheDirectory: directory)
    let recreated = try await recreatedLoader.load(source: source)
    XCTAssertEqual(recreated.packages.first?.latest, "1.1.0")

    let requests = RegistryURLProtocol.requests()
    XCTAssertEqual(requests.count, 3)
    XCTAssertEqual(requests[1].ifNoneMatch, "\"registry-v1\"")
    XCTAssertEqual(requests[2].ifNoneMatch, "\"registry-v2\"")
  }

  func testNotModifiedWithCorruptCacheRetriesWithoutValidators() async throws {
    let source = "https://registry.example.test/index.json"
    RegistryURLProtocol.enqueue(
      .init(
        statusCode: 200,
        headers: ["ETag": "\"registry-v1\""],
        data: registryData(version: "1.0.0")
      )
    )

    let loader = WidgetPackageRegistryLoader(session: session, cacheDirectory: directory)
    _ = try await loader.load(source: source)

    let index = try XCTUnwrap(
      FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        .first { $0.lastPathComponent.hasSuffix(".json") && !$0.lastPathComponent.hasSuffix(".metadata.json") }
    )
    try Data("not json".utf8).write(to: index, options: .atomic)

    RegistryURLProtocol.enqueue(.init(statusCode: 304, headers: [:], data: Data()))
    RegistryURLProtocol.enqueue(
      .init(
        statusCode: 200,
        headers: ["ETag": "\"registry-v2\""],
        data: registryData(version: "1.1.0")
      )
    )

    let refreshed = try await loader.load(source: source)
    XCTAssertEqual(refreshed.packages.first?.latest, "1.1.0")

    let requests = RegistryURLProtocol.requests()
    XCTAssertEqual(requests.count, 3)
    XCTAssertNil(requests[1].ifNoneMatch)
    XCTAssertNil(requests[1].ifModifiedSince)
    XCTAssertNil(requests[2].ifNoneMatch)
    XCTAssertNil(requests[2].ifModifiedSince)
  }

  func testFileRegistryDoesNotUseRemoteSessionOrCache() async throws {
    let index = directory.appending(path: "local-index.json")
    try registryData(version: "2.0.0").write(to: index, options: .atomic)
    let cache = directory.appending(path: "cache", directoryHint: .isDirectory)

    let loader = WidgetPackageRegistryLoader(session: session, cacheDirectory: cache)
    let registry = try await loader.load(source: index.path)

    XCTAssertEqual(registry.packages.first?.latest, "2.0.0")
    XCTAssertTrue(RegistryURLProtocol.requests().isEmpty)
    XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path))
  }

  private func registryData(version: String) -> Data {
    Data(
      """
      {
        "registry_version": 1,
        "packages": [{
          "name": "example",
          "kind": "widget",
          "latest": "\(version)",
          "description": "Example package",
          "categories": ["test"],
          "versions": [{
            "version": "\(version)",
            "archive": "https://example.test/example-\(version).tar.gz",
            "sha256": "0000000000000000000000000000000000000000000000000000000000000000"
          }]
        }]
      }
      """.utf8
    )
  }
}

private final class RegistryURLProtocol: URLProtocol, @unchecked Sendable {
  struct StubResponse: Sendable {
    let statusCode: Int
    let headers: [String: String]
    let data: Data
  }

  struct RequestSnapshot: Equatable, Sendable {
    let ifNoneMatch: String?
    let ifModifiedSince: String?
    let cacheControl: String?
    let cachePolicy: URLRequest.CachePolicy
  }

  private struct State {
    var responses: [StubResponse] = []
    var requests: [RequestSnapshot] = []
  }

  private static let state = LockedState(State())

  static func reset() {
    state.withLock { state in
      state.responses.removeAll()
      state.requests.removeAll()
    }
  }

  static func enqueue(_ response: StubResponse) {
    state.withLock { $0.responses.append(response) }
  }

  static func requests() -> [RequestSnapshot] {
    state.withLock { $0.requests }
  }

  override class func canInit(with request: URLRequest) -> Bool {
    true
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    let response = Self.state.withLock { state -> StubResponse? in
      state.requests.append(
        RequestSnapshot(
          ifNoneMatch: request.value(forHTTPHeaderField: "If-None-Match"),
          ifModifiedSince: request.value(forHTTPHeaderField: "If-Modified-Since"),
          cacheControl: request.value(forHTTPHeaderField: "Cache-Control"),
          cachePolicy: request.cachePolicy
        )
      )
      guard !state.responses.isEmpty else { return nil }
      return state.responses.removeFirst()
    }

    guard let response else {
      client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
      return
    }
    guard
      let httpResponse = HTTPURLResponse(
        url: request.url!,
        statusCode: response.statusCode,
        httpVersion: "HTTP/1.1",
        headerFields: response.headers
      )
    else {
      client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
      return
    }

    client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
    if !response.data.isEmpty {
      client?.urlProtocol(self, didLoad: response.data)
    }
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}
