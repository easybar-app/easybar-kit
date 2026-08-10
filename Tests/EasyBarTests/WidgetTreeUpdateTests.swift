import XCTest

@testable import EasyBarKit

final class WidgetTreeUpdateTests: XCTestCase {
  private let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return decoder
  }()

  func testSupportedProtocolVersionIsAccepted() throws {
    let update = try decoder.decode(
      WidgetTreeUpdate.self,
      from: Data(#"{"protocol_version":1,"type":"ready"}"#.utf8)
    )

    XCTAssertTrue(update.isSupportedProtocolVersion)
  }

  func testUnexpectedProtocolVersionIsRejected() throws {
    let update = try decoder.decode(
      WidgetTreeUpdate.self,
      from: Data(#"{"protocol_version":2,"type":"ready"}"#.utf8)
    )

    XCTAssertFalse(update.isSupportedProtocolVersion)
  }

  func testClearRootPayloadIsDecoded() throws {
    let update = try decoder.decode(
      WidgetTreeUpdate.self,
      from: Data(#"{"protocol_version":1,"type":"clear_root","root":"clock"}"#.utf8)
    )

    XCTAssertTrue(update.isClearRoot)
    XCTAssertEqual(update.clearRootID, "clock")
  }

  func testCommandCancellationPayloadIsDecoded() throws {
    let message = try WidgetRuntimeProtocolDecoder().decodeMessage(
      from: #"{"protocol_version":1,"type":"command_cancel","token":"job-1"}"#
    )

    guard case .commandCancel(let token) = message else {
      return XCTFail("Expected command cancellation message")
    }
    XCTAssertEqual(token, "job-1")
  }

  func testDirectExecutableCommandPayloadIsDecoded() throws {
    let message = try WidgetRuntimeProtocolDecoder().decodeMessage(
      from:
        #"{"protocol_version":1,"type":"command_request","token":"job-1","arguments":["printf","%s","hello world"],"sync":false}"#
    )

    guard
      case .commandRequest(
        let token, let invocation, let isSynchronous, _, _, let widget, let operation) = message
    else {
      return XCTFail("Expected command request message")
    }
    XCTAssertEqual(token, "job-1")
    XCTAssertEqual(invocation, .executable(["printf", "%s", "hello world"]))
    XCTAssertFalse(isSynchronous)
    XCTAssertNil(widget)
    XCTAssertNil(operation)
  }

  func testCommandLogContextIsDecoded() throws {
    let message = try WidgetRuntimeProtocolDecoder().decodeMessage(
      from:
        #"{"protocol_version":1,"type":"command_request","token":"job-1","arguments":["printf","hello"],"sync":false,"widget":"github-inbox","operation":"refresh"}"#
    )

    guard case .commandRequest(_, _, _, _, _, let widget, let operation) = message else {
      return XCTFail("Expected command request message")
    }
    XCTAssertEqual(widget, "github-inbox")
    XCTAssertEqual(operation, "refresh")
  }

  func testCommandPayloadRejectsShellAndArgumentsTogether() throws {
    XCTAssertThrowsError(
      try WidgetRuntimeProtocolDecoder().decodeMessage(
        from:
          #"{"protocol_version":1,"type":"command_request","token":"job-1","command":"printf x","arguments":["printf","x"],"sync":false}"#
      )
    )
  }

  func testCommandAndTimerTokensAreBounded() throws {
    let decoder = WidgetRuntimeProtocolDecoder()

    XCTAssertThrowsError(
      try decoder.decodeMessage(
        from:
          #"{"protocol_version":1,"type":"command_request","token":"","arguments":["true"],"sync":false}"#
      )
    )

    let oversized = String(
      repeating: "x", count: WidgetRuntimeProtocolDecoder.maximumTokenBytes + 1)
    let encodedOversized = try XCTUnwrap(
      String(data: JSONEncoder().encode(oversized), encoding: .utf8)
    )
    XCTAssertThrowsError(
      try decoder.decodeMessage(
        from:
          "{\"protocol_version\":1,\"type\":\"timer_request\",\"token\":\(encodedOversized),\"delay_seconds\":1}"
      )
    )

    XCTAssertThrowsError(
      try decoder.decodeMessage(
        from: #"{"protocol_version":1,"type":"timer_cancel","token":"bad\nvalue"}"#
      )
    )
  }

  func testTimerRequestAndCancellationPayloadsAreDecoded() throws {
    let request = try WidgetRuntimeProtocolDecoder().decodeMessage(
      from: #"{"protocol_version":1,"type":"timer_request","token":"timer-1","delay_seconds":2.5}"#
    )
    guard case .timerRequest(let token, let delaySeconds) = request else {
      return XCTFail("Expected timer request")
    }
    XCTAssertEqual(token, "timer-1")
    XCTAssertEqual(delaySeconds, 2.5)

    let cancellation = try WidgetRuntimeProtocolDecoder().decodeMessage(
      from: #"{"protocol_version":1,"type":"timer_cancel","token":"timer-1"}"#
    )
    guard case .timerCancel(let cancelledToken) = cancellation else {
      return XCTFail("Expected timer cancellation")
    }
    XCTAssertEqual(cancelledToken, "timer-1")
  }

  func testInboxReplacementPayloadIsDecoded() throws {
    let message = try WidgetRuntimeProtocolDecoder().decodeMessage(
      from:
        #"{"protocol_version":1,"type":"inbox_replace","source":"gitlab","items":[{"id":"one","title":"Review","body":"**Ready**","format":"markdown","severity":"success"}]}"#
    )

    guard case .inboxReplace(let snapshot) = message else {
      return XCTFail("Expected inbox replacement message")
    }
    XCTAssertEqual(snapshot.source, "gitlab")
    XCTAssertEqual(snapshot.items.first?.title, "Review")
    XCTAssertEqual(snapshot.items.first?.resolvedFormat, .markdown)
    XCTAssertEqual(snapshot.items.first?.resolvedSeverity, .success)
  }

  func testInboxClearRejectsEmptySource() throws {
    XCTAssertThrowsError(
      try WidgetRuntimeProtocolDecoder().decodeMessage(
        from: #"{"protocol_version":1,"type":"inbox_clear","source":""}"#
      )
    )
  }

  func testInboxConfigurationPayloadIsDecoded() throws {
    let message = try WidgetRuntimeProtocolDecoder().decodeMessage(
      from:
        ##"{"protocol_version":1,"type":"inbox_configure","source":"GitLab","order":20,"presentation":{"name":"GitLab","icon":"GL","color":"#FC6D26"},"actions":[{"id":"sync","title":"Refresh","include_in_refresh_all":true},{"id":"settings","title":"Settings","children":[{"id":"interval","title":"Refresh every 5 minutes","enabled":false}]}]}"##
    )

    guard case .inboxConfigure(let configuration) = message else {
      return XCTFail("Expected inbox configuration message")
    }
    XCTAssertEqual(configuration.source, "GitLab")
    XCTAssertEqual(configuration.order, 20)
    XCTAssertEqual(
      configuration.presentation,
      InboxSourcePresentation(name: "GitLab", icon: "GL", color: "#FC6D26")
    )
    XCTAssertEqual(
      configuration.actions,
      [
        InboxAction(id: "sync", title: "Refresh", includeInRefreshAll: true),
        InboxAction(
          id: "settings",
          title: "Settings",
          children: [
            InboxAction(id: "interval", title: "Refresh every 5 minutes", enabled: false)
          ]
        ),
      ]
    )
  }

  func testStorageRequestsAreDecodedAndBoundedToPlainSegments() throws {
    let get = try WidgetRuntimeProtocolDecoder().decodeMessage(
      from:
        #"{"protocol_version":1,"type":"storage_request","token":"storage-1","operation":"get","widget":"github-inbox","key":"merge_method"}"#
    )
    guard case .storageRequest(let token, let widget, let key, let operation, let value) = get else {
      return XCTFail("Expected storage request")
    }
    XCTAssertEqual(token, "storage-1")
    XCTAssertEqual(widget, "github-inbox")
    XCTAssertEqual(key, "merge_method")
    XCTAssertEqual(operation, .get)
    XCTAssertNil(value)

    let set = try WidgetRuntimeProtocolDecoder().decodeMessage(
      from:
        #"{"protocol_version":1,"type":"storage_request","token":"storage-2","operation":"set","widget":"github-inbox","key":"merge_method","value":"rebase"}"#
    )
    guard case .storageRequest(_, _, _, let setOperation, let setValue) = set else {
      return XCTFail("Expected storage request")
    }
    XCTAssertEqual(setOperation, .set)
    XCTAssertEqual(setValue, .string("rebase"))

    XCTAssertThrowsError(
      try WidgetRuntimeProtocolDecoder().decodeMessage(
        from:
          #"{"protocol_version":1,"type":"storage_request","token":"storage-3","operation":"get","widget":"../app","key":"merge_method"}"#
      )
    )
    XCTAssertThrowsError(
      try WidgetRuntimeProtocolDecoder().decodeMessage(
        from:
          #"{"protocol_version":1,"type":"storage_request","token":"storage-4","operation":"set","widget":"github-inbox","key":"merge_method"}"#
      )
    )
  }

  func testImagePathDecodesToPathSource() throws {
    let node = try decodeNode(imageFields: ",\"image_path\":\"/tmp/icon.svg\"")

    XCTAssertEqual(node.imagePath, "/tmp/icon.svg")
    XCTAssertEqual(node.imageSource, .path("/tmp/icon.svg"))
  }

  func testImageSVGDecodesToInlineSource() throws {
    let svg = #"<svg viewBox=\"0 0 1 1\"></svg>"#
    let encoded = try XCTUnwrap(String(data: JSONEncoder().encode(svg), encoding: .utf8))
    let node = try decodeNode(imageFields: ",\"image_svg\":\(encoded)")

    XCTAssertEqual(node.imageSvg, svg)
    XCTAssertEqual(node.imageSource, .svg(svg))
  }

  func testBothImageFieldsProduceNoSource() throws {
    let node = try decodeNode(
      imageFields: ",\"image_path\":\"/tmp/icon.svg\",\"image_svg\":\"<svg/>\""
    )

    XCTAssertNil(node.imageSource)
  }

  func testOversizedInlineSVGProducesNoSource() throws {
    let oversized = "<svg>" + String(repeating: " ", count: 256 * 1024) + "</svg>"
    let encoded = try XCTUnwrap(String(data: JSONEncoder().encode(oversized), encoding: .utf8))
    let node = try decodeNode(imageFields: ",\"image_svg\":\(encoded)")

    XCTAssertNil(node.imageSource)
  }

  private func decodeNode(imageFields: String) throws -> WidgetNodeState {
    let message = try WidgetRuntimeProtocolDecoder().decodeMessage(
      from: """
        {"protocol_version":1,"type":"tree","root":"icon","nodes":[{"id":"icon","root":"icon","kind":"item","position":"right","order":0,"icon":"","text":"","visible":true\(imageFields)}]}
        """
    )

    guard case .tree(_, let nodes) = message else {
      throw WidgetRuntimeProtocolError.invalidPayload("expected tree")
    }
    return try XCTUnwrap(nodes.first)
  }
}
