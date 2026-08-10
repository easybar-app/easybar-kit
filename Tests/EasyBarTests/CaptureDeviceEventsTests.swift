import EasyBarShared
import XCTest

@testable import EasyBarKit

@MainActor
final class CaptureDeviceEventsTests: XCTestCase {
  private static func makeHub() -> EventHub {
    EventHub(
      logger: ProcessLogger(label: "capture-events.tests", minimumLevel: .error),
      enqueueLuaEvent: { _ in }
    )
  }

  func testPublishesCurrentSnapshotForNewSubscription() async throws {
    let hub = Self.makeHub()
    let inventory = FakeCaptureDeviceInventoryMonitor(
      devices: [Self.camera(active: true)]
    )
    let source = CaptureDeviceEvents(
      logger: ProcessLogger(label: "capture-events.tests", minimumLevel: .error),
      eventHub: hub,
      inventoryMonitor: inventory
    )

    source.start()
    let stream = await hub.subscribe(
      eventNames: [AppEvent.captureActivityChanged.rawValue]
    )
    let nextPayload = Task { await Self.next(from: stream) }

    source.publishCurrentSnapshot(
      for: [AppEvent.captureActivityChanged.rawValue]
    )

    let value = await nextPayload.value
    let payload = try XCTUnwrap(value)
    XCTAssertEqual(payload.eventName, AppEvent.captureActivityChanged.rawValue)
    XCTAssertEqual(payload.capture?.active, true)
    XCTAssertEqual(payload.capture?.cameraActive, true)
    XCTAssertEqual(payload.capture?.microphoneActive, false)
    XCTAssertEqual(payload.luaPayload.capture, payload.capture)
  }

  func testActivityChangeEmitsSpecificAndAggregateEvents() async throws {
    let hub = Self.makeHub()
    let inventory = FakeCaptureDeviceInventoryMonitor(devices: [])
    let source = CaptureDeviceEvents(
      logger: ProcessLogger(label: "capture-events.tests", minimumLevel: .error),
      eventHub: hub,
      inventoryMonitor: inventory
    )

    source.start()
    let stream = await hub.subscribe(
      eventNames: [
        AppEvent.microphoneActivityChanged.rawValue,
        AppEvent.captureActivityChanged.rawValue,
      ]
    )
    let payloadsTask = Task { await Self.next(count: 2, from: stream) }

    inventory.update([Self.microphone(active: true)])

    let payloads = await payloadsTask.value
    XCTAssertEqual(
      payloads.map(\.eventName),
      [
        AppEvent.microphoneActivityChanged.rawValue,
        AppEvent.captureActivityChanged.rawValue,
      ]
    )
    XCTAssertTrue(payloads.allSatisfy { $0.capture?.microphoneActive == true })
  }

  func testActiveCameraSwitchEmitsSpecificAndAggregateEvents() async {
    let hub = Self.makeHub()
    let firstCamera = CaptureDeviceState(
      id: "camera-1",
      name: "First Camera",
      kind: .camera,
      connected: true,
      active: true
    )
    let secondCamera = CaptureDeviceState(
      id: "camera-2",
      name: "Second Camera",
      kind: .camera,
      connected: true,
      active: false
    )
    let inventory = FakeCaptureDeviceInventoryMonitor(
      devices: [firstCamera, secondCamera]
    )
    let source = CaptureDeviceEvents(
      logger: ProcessLogger(label: "capture-events.tests", minimumLevel: .error),
      eventHub: hub,
      inventoryMonitor: inventory
    )

    source.start()
    let stream = await hub.subscribe(
      eventNames: [
        AppEvent.cameraActivityChanged.rawValue,
        AppEvent.captureActivityChanged.rawValue,
      ]
    )
    let payloadsTask = Task { await Self.next(count: 2, from: stream) }

    inventory.update([
      CaptureDeviceState(
        id: firstCamera.id,
        name: firstCamera.name,
        kind: firstCamera.kind,
        connected: true,
        active: false
      ),
      CaptureDeviceState(
        id: secondCamera.id,
        name: secondCamera.name,
        kind: secondCamera.kind,
        connected: true,
        active: true
      ),
    ])

    let payloads = await payloadsTask.value
    XCTAssertEqual(
      payloads.map(\.eventName),
      [
        AppEvent.cameraActivityChanged.rawValue,
        AppEvent.captureActivityChanged.rawValue,
      ]
    )
    XCTAssertTrue(payloads.allSatisfy { $0.capture?.cameraActive == true })
  }

  func testConnectionChangeEmitsDeviceInventoryEvent() async throws {
    let hub = Self.makeHub()
    let inventory = FakeCaptureDeviceInventoryMonitor(devices: [])
    let source = CaptureDeviceEvents(
      logger: ProcessLogger(label: "capture-events.tests", minimumLevel: .error),
      eventHub: hub,
      inventoryMonitor: inventory
    )

    source.start()
    let stream = await hub.subscribe(
      eventNames: [AppEvent.captureDevicesChanged.rawValue]
    )
    let nextPayload = Task { await Self.next(from: stream) }

    inventory.update([Self.camera(active: false)])

    let value = await nextPayload.value
    let payload = try XCTUnwrap(value)
    XCTAssertEqual(payload.eventName, AppEvent.captureDevicesChanged.rawValue)
    XCTAssertEqual(payload.capture?.cameras.map(\.id), ["camera-1"])
    XCTAssertEqual(payload.capture?.active, false)
  }

  func testCameraAndMicrophoneChangesArePublishedImmediately() {
    let hub = Self.makeHub()
    let inventory = FakeCaptureDeviceInventoryMonitor(
      devices: [Self.camera(active: true), Self.microphone(active: true)]
    )
    let source = CaptureDeviceEvents(
      logger: ProcessLogger(label: "capture-events.tests", minimumLevel: .error),
      eventHub: hub,
      inventoryMonitor: inventory
    )

    source.start()

    inventory.update([Self.camera(active: false), Self.microphone(active: true)])
    XCTAssertFalse(source.snapshot.cameraActive)
    XCTAssertTrue(source.snapshot.microphoneActive)

    inventory.update([Self.camera(active: false), Self.microphone(active: false)])
    XCTAssertFalse(source.snapshot.cameraActive)
    XCTAssertFalse(source.snapshot.microphoneActive)
    XCTAssertFalse(source.snapshot.active)
  }

  func testMicrophoneOnlyChangesRemainImmediate() {
    let hub = Self.makeHub()
    let inventory = FakeCaptureDeviceInventoryMonitor(devices: [])
    let source = CaptureDeviceEvents(
      logger: ProcessLogger(label: "capture-events.tests", minimumLevel: .error),
      eventHub: hub,
      inventoryMonitor: inventory
    )

    source.start()

    inventory.update([Self.microphone(active: true)])
    XCTAssertTrue(source.snapshot.microphoneActive)
    XCTAssertTrue(source.snapshot.active)

    inventory.update([Self.microphone(active: false)])
    XCTAssertFalse(source.snapshot.microphoneActive)
    XCTAssertFalse(source.snapshot.active)
  }

  func testMicrophoneDeviceFallbackDetectsMicrophoneOnlyCapture() {
    var resolver = MicrophoneActivityResolver()

    XCTAssertFalse(resolver.resolve(processActive: false, deviceActive: false))
    XCTAssertTrue(resolver.resolve(processActive: false, deviceActive: true))
    XCTAssertFalse(resolver.resolve(processActive: false, deviceActive: false))
  }

  func testMicrophoneDeviceFallbackDoesNotKeepCameraAudioAlive() {
    var resolver = MicrophoneActivityResolver()

    resolver.setCameraActive(true)
    XCTAssertTrue(resolver.resolve(processActive: true, deviceActive: true))

    resolver.setCameraActive(false)
    XCTAssertFalse(
      resolver.resolve(processActive: false, deviceActive: true),
      "A device that remains running after camera shutdown must not keep microphone activity true."
    )
    XCTAssertFalse(resolver.deviceFallbackEnabled)

    XCTAssertFalse(resolver.resolve(processActive: false, deviceActive: false))
    XCTAssertTrue(resolver.deviceFallbackEnabled)
    XCTAssertTrue(
      resolver.resolve(processActive: false, deviceActive: true),
      "Device fallback should be available again for the next microphone-only session."
    )
  }

  func testProcessInputRemainsAuthoritativeDuringCameraCapture() {
    var resolver = MicrophoneActivityResolver()

    resolver.setCameraActive(true)
    XCTAssertFalse(resolver.resolve(processActive: false, deviceActive: true))
    XCTAssertTrue(resolver.resolve(processActive: true, deviceActive: true))
  }

  func testSourceStartsAndStopsInventoryMonitor() {
    let hub = Self.makeHub()
    let inventory = FakeCaptureDeviceInventoryMonitor(devices: [])
    let source = CaptureDeviceEvents(
      logger: ProcessLogger(label: "capture-events.tests", minimumLevel: .error),
      eventHub: hub,
      inventoryMonitor: inventory
    )

    source.start()
    source.start()
    XCTAssertEqual(inventory.startCount, 1)

    source.stop()
    source.stop()
    XCTAssertEqual(inventory.stopCount, 1)
    XCTAssertEqual(source.snapshot, .empty)
  }

  private static func camera(active: Bool) -> CaptureDeviceState {
    CaptureDeviceState(
      id: "camera-1",
      name: "Camera",
      kind: .camera,
      connected: true,
      active: active
    )
  }

  private static func microphone(active: Bool) -> CaptureDeviceState {
    CaptureDeviceState(
      id: "microphone-1",
      name: "Microphone",
      kind: .microphone,
      connected: true,
      active: active
    )
  }

  private static func next(
    from stream: AsyncStream<EasyBarEventPayload>
  ) async -> EasyBarEventPayload? {
    var iterator = stream.makeAsyncIterator()
    return await iterator.next()
  }

  private static func next(
    count: Int,
    from stream: AsyncStream<EasyBarEventPayload>
  ) async -> [EasyBarEventPayload] {
    var iterator = stream.makeAsyncIterator()
    var payloads: [EasyBarEventPayload] = []
    for _ in 0..<count {
      guard let payload = await iterator.next() else { break }
      payloads.append(payload)
    }
    return payloads
  }
}

@MainActor
private final class FakeCaptureDeviceInventoryMonitor: CaptureDeviceInventoryMonitoring {
  var onChange: (() -> Void)?
  private(set) var startCount = 0
  private(set) var stopCount = 0
  private(set) var devices: [CaptureDeviceState]

  init(devices: [CaptureDeviceState]) {
    self.devices = devices
  }

  func start() {
    startCount += 1
  }

  func stop() {
    stopCount += 1
  }

  func update(_ devices: [CaptureDeviceState]) {
    self.devices = devices
    onChange?()
  }
}
