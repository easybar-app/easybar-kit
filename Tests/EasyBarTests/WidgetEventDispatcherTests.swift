import XCTest

@testable import EasyBarKit

private actor DispatchedValueRecorder {
  private(set) var values: [Int] = []

  func append(_ value: Int) {
    values.append(value)
  }
}

@MainActor
final class WidgetEventDispatcherTests: XCTestCase {
  func testOperationsCompleteInEnqueueOrder() async {
    let dispatcher = WidgetEventDispatcher()
    let recorder = DispatchedValueRecorder()

    dispatcher.enqueue {
      try? await Task.sleep(for: .milliseconds(20))
      await recorder.append(1)
    }
    dispatcher.enqueue {
      await recorder.append(2)
    }

    await dispatcher.waitUntilIdle()

    let values = await recorder.values
    XCTAssertEqual(values, [1, 2])
  }
}
