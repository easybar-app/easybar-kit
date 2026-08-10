import Combine
import XCTest

@testable import EasyBarKit

@MainActor
final class WidgetStoreTests: XCTestCase {
  func testIdenticalReplacementDoesNotRepublishStore() throws {
    let store = WidgetStore()
    let node = try makeNode(id: "stable", root: "root", text: "unchanged")
    store.apply(owner: .scripted(root: "root"), nodes: [node])

    var publicationCount = 0
    let cancellable = store.objectWillChange.sink {
      publicationCount += 1
    }

    let result = store.apply(owner: .scripted(root: "root"), nodes: [node])

    XCTAssertTrue(result.rejectedNodeIDs.isEmpty)
    XCTAssertEqual(publicationCount, 0)
    withExtendedLifetime(cancellable) {}
  }

  func testCrossRootNodeCollisionDoesNotOverwriteOrDeleteOwner() throws {
    let store = WidgetStore()
    let original = try makeNode(id: "shared", root: "first", text: "original")
    let collision = try makeNode(id: "shared", root: "second", text: "replacement")

    store.apply(owner: .scripted(root: "first"), nodes: [original])
    let result = store.apply(owner: .scripted(root: "second"), nodes: [collision])
    store.clear(owners: [.scripted(root: "second")])

    XCTAssertEqual(result.conflictingNodeIDs, ["shared"])
    XCTAssertEqual(store.topLevelNodes(for: .right), [original])
  }

  func testApplyRejectsMismatchedRootsAndDuplicateIDs() throws {
    let store = WidgetStore()
    let first = try makeNode(id: "duplicate", root: "expected", text: "first")
    let duplicate = try makeNode(id: "duplicate", root: "expected", text: "second")
    let mismatch = try makeNode(id: "mismatch", root: "other", text: "mismatch")

    let result = store.apply(
      owner: .scripted(root: "expected"),
      nodes: [first, duplicate, mismatch]
    )

    XCTAssertEqual(result.duplicateNodeIDs, ["duplicate"])
    XCTAssertEqual(result.mismatchedRootNodeIDs, ["mismatch"])
    XCTAssertTrue(store.topLevelNodes(for: .right).isEmpty)
  }

  func testRejectedReplacementPreservesPreviousTree() throws {
    let store = WidgetStore()
    let original = try makeNode(id: "original", root: "root", text: "original")
    let validReplacement = try makeNode(id: "replacement", root: "root", text: "replacement")
    let invalidReplacement = try makeNode(id: "invalid", root: "other", text: "invalid")

    store.apply(owner: .scripted(root: "root"), nodes: [original])
    let result = store.apply(
      owner: .scripted(root: "root"),
      nodes: [validReplacement, invalidReplacement]
    )

    XCTAssertEqual(result.mismatchedRootNodeIDs, [invalidReplacement.id])
    XCTAssertEqual(store.topLevelNodes(for: .right), [original])
  }

  func testParentCycleRejectsReplacementAndPreservesPreviousTree() throws {
    let store = WidgetStore()
    let original = try makeNode(id: "original", root: "root", text: "original")
    let first = try makeNode(id: "first", root: "root", text: "first", parent: "second")
    let second = try makeNode(id: "second", root: "root", text: "second", parent: "first")

    store.apply(owner: .scripted(root: "root"), nodes: [original])
    let result = store.apply(owner: .scripted(root: "root"), nodes: [first, second])

    XCTAssertEqual(result.cyclicNodeIDs, [first.id, second.id])
    XCTAssertEqual(store.topLevelNodes(for: .right), [original])
  }

  func testLongAcyclicParentChainIsAccepted() throws {
    let store = WidgetStore()
    let count = 1_000
    let nodes = try (0..<count).map { index in
      try makeNode(
        id: "node-\(index)",
        root: "root",
        text: "node",
        parent: index == 0 ? nil : "node-0"
      )
    }

    let result = store.apply(owner: .scripted(root: "root"), nodes: nodes)

    XCTAssertTrue(result.rejectedNodeIDs.isEmpty)
    XCTAssertEqual(store.topLevelNodes(for: .right), [nodes[0]])
  }

  func testOversizedScriptedTreeIsRejected() throws {
    let store = WidgetStore()
    let nodes = try (0...WidgetStore.maximumScriptedNodeCount).map { index in
      try makeNode(id: "node-\(index)", root: "root", text: "node")
    }

    let result = store.apply(owner: .scripted(root: "root"), nodes: nodes)

    XCTAssertEqual(result.oversizedTreeNodeIDs, [nodes.last!.id])
    XCTAssertTrue(store.topLevelNodes(for: .right).isEmpty)
  }

  func testOverdepthScriptedTreeIsRejected() throws {
    let store = WidgetStore()
    let nodes = try (0...(WidgetStore.maximumScriptedDepth + 1)).map { index in
      try makeNode(
        id: "node-\(index)",
        root: "root",
        text: "node",
        parent: index == 0 ? nil : "node-\(index - 1)"
      )
    }

    let result = store.apply(owner: .scripted(root: "root"), nodes: nodes)

    XCTAssertEqual(result.overdepthNodeIDs, [nodes.last!.id])
    XCTAssertTrue(store.topLevelNodes(for: .right).isEmpty)
  }

  func testRelationshipIndexesTrackReplacementAndClear() throws {
    let store = WidgetStore()
    let root = try makeNode(id: "root", root: "root", text: "root")
    let child = try makeNode(id: "child", root: "root", text: "child", parent: "root")
    let anchor = try makeNode(
      id: "anchor",
      root: "root",
      text: "anchor",
      parent: "root",
      role: "popup-anchor"
    )
    let popup = try makeNode(
      id: "popup",
      root: "root",
      text: "popup",
      parent: "root",
      role: "popup-content"
    )

    store.apply(owner: .scripted(root: "root"), nodes: [popup, child, root, anchor])

    XCTAssertEqual(store.topLevelNodes(for: .right), [root])
    XCTAssertEqual(store.children(of: "root"), [child])
    XCTAssertEqual(store.anchorChildren(of: "root"), [anchor])
    XCTAssertEqual(store.popupChildren(of: "root"), [popup])

    store.apply(owner: .scripted(root: "root"), nodes: [root])

    XCTAssertTrue(store.children(of: "root").isEmpty)
    XCTAssertTrue(store.anchorChildren(of: "root").isEmpty)
    XCTAssertTrue(store.popupChildren(of: "root").isEmpty)
  }

  func testScriptedRootCannotReplaceNativeRootWithSameName() throws {
    let store = WidgetStore()
    let native = try makeNode(id: "shared", root: "shared", text: "native")
    let scripted = try makeNode(id: "shared", root: "shared", text: "scripted")

    store.apply(owner: .native(root: "shared"), nodes: [native])
    let result = store.apply(owner: .scripted(root: "shared"), nodes: [scripted])
    store.clear(owners: [.scripted(root: "shared")])

    XCTAssertEqual(result.conflictingNodeIDs, ["shared"])
    XCTAssertEqual(store.topLevelNodes(for: .right), [native])
  }

  func testScriptedNodeCannotAttachToNativeParent() throws {
    let store = WidgetStore()
    let native = try makeNode(id: "native-parent", root: "native", text: "native")
    let scripted = try makeNode(
      id: "scripted-child",
      root: "scripted",
      text: "scripted",
      parent: native.id
    )

    store.apply(owner: .native(root: "native"), nodes: [native])
    let result = store.apply(owner: .scripted(root: "scripted"), nodes: [scripted])

    XCTAssertEqual(result.invalidParentNodeIDs, [scripted.id])
    XCTAssertTrue(store.children(of: native.id).isEmpty)
    XCTAssertEqual(store.topLevelNodes(for: .right), [native])
  }

  private func makeNode(
    id: String,
    root: String,
    text: String,
    parent: String? = nil,
    role: String? = nil
  ) throws -> WidgetNodeState {
    let parentField = parent.map { "\"parent\": \"\($0)\"," } ?? ""
    let roleField = role.map { "\"role\": \"\($0)\"," } ?? ""
    let payload = """
      {
        "id": "\(id)",
        "root": "\(root)",
        \(parentField)
        \(roleField)
        "kind": "item",
        "position": "right",
        "order": 0,
        "icon": "",
        "text": "\(text)",
        "visible": true
      }
      """
    return try JSONDecoder().decode(WidgetNodeState.self, from: Data(payload.utf8))
  }
}
