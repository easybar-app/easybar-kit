import AudioToolbox
import CoreAudio
import CoreMediaIO
import EasyBarShared
import Foundation

/// Demand-driven camera and microphone event source for subscribed consumers.
@MainActor
final class CaptureDeviceEvents {
  static let orderedEvents: [AppEvent] = [
    .captureDevicesChanged,
    .cameraActivityChanged,
    .microphoneActivityChanged,
    .captureActivityChanged,
  ]

  static let eventNames = Set(orderedEvents.map(\.rawValue))

  private let logger: ProcessLogger
  private let eventHub: EventHub
  private let inventoryMonitor: CaptureDeviceInventoryMonitoring
  private var started = false
  private(set) var snapshot = CaptureDeviceSnapshot.empty

  init(
    logger: ProcessLogger,
    eventHub: EventHub,
    inventoryMonitor: CaptureDeviceInventoryMonitoring? = nil
  ) {
    self.logger = logger
    self.eventHub = eventHub
    self.inventoryMonitor =
      inventoryMonitor ?? SystemCaptureDeviceInventoryMonitor(logger: logger)
  }

  /// Starts capture-device observation when at least one subscriber requires it.
  func start() {
    guard !started else { return }
    started = true

    inventoryMonitor.onChange = { [weak self] in
      self?.handleInventoryChange()
    }
    inventoryMonitor.start()
    snapshot = Self.makeSnapshot(from: inventoryMonitor.devices)

    logger.debug(
      "subscribed capture device events",
      .field("cameras", snapshot.cameras.count),
      .field("microphones", snapshot.microphones.count)
    )
  }

  /// Stops all device and activity observers.
  func stop() {
    guard started else { return }
    started = false
    inventoryMonitor.stop()
    inventoryMonitor.onChange = nil
    snapshot = .empty
    logger.debug("unsubscribed capture device events")
  }

  /// Publishes the current snapshot for newly added subscriptions.
  func publishCurrentSnapshot(for eventNames: Set<String>) {
    guard started else { return }

    let events = Self.orderedEvents.filter { eventNames.contains($0.rawValue) }
    emit(events, snapshot: snapshot)
  }

  private func handleInventoryChange() {
    guard started else { return }
    applySnapshot(Self.makeSnapshot(from: inventoryMonitor.devices))
  }

  private func applySnapshot(_ next: CaptureDeviceSnapshot) {
    let previous = snapshot
    snapshot = next

    let cameraActivityChanged =
      Self.activeDeviceIDs(in: previous.cameras) != Self.activeDeviceIDs(in: next.cameras)
    let microphoneActivityChanged =
      Self.activeDeviceIDs(in: previous.microphones) != Self.activeDeviceIDs(in: next.microphones)

    var events: [AppEvent] = []
    if Self.deviceIdentities(in: previous) != Self.deviceIdentities(in: next) {
      events.append(.captureDevicesChanged)
    }
    if cameraActivityChanged {
      events.append(.cameraActivityChanged)
    }
    if microphoneActivityChanged {
      events.append(.microphoneActivityChanged)
    }
    if cameraActivityChanged || microphoneActivityChanged {
      events.append(.captureActivityChanged)
    }

    guard !events.isEmpty else { return }

    logger.debug(
      "capture device state changed",
      .field("events", events.map(\.rawValue).joined(separator: ",")),
      .field("camera_active", next.cameraActive),
      .field("microphone_active", next.microphoneActive),
      .field("cameras", next.cameras.count),
      .field("microphones", next.microphones.count)
    )
    emit(events, snapshot: next)
  }

  private func emit(_ events: [AppEvent], snapshot: CaptureDeviceSnapshot) {
    guard !events.isEmpty else { return }

    let eventHub = self.eventHub
    Task {
      for event in events {
        await eventHub.emit(
          .app(
            event,
            source: "capture_devices",
            capture: snapshot
          )
        )
      }
    }
  }

  private static func makeSnapshot(
    from devices: [CaptureDeviceState]
  ) -> CaptureDeviceSnapshot {
    let cameras =
      devices
      .filter { $0.kind == .camera }
      .sorted(by: deviceSort)
    let microphones =
      devices
      .filter { $0.kind == .microphone }
      .sorted(by: deviceSort)

    return CaptureDeviceSnapshot(cameras: cameras, microphones: microphones)
  }

  private static func deviceSort(_ lhs: CaptureDeviceState, _ rhs: CaptureDeviceState) -> Bool {
    if lhs.name != rhs.name {
      return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
    return lhs.id < rhs.id
  }

  private static func deviceIdentities(
    in snapshot: CaptureDeviceSnapshot
  ) -> [CaptureDeviceIdentity] {
    (snapshot.cameras + snapshot.microphones).map {
      CaptureDeviceIdentity(
        id: $0.id,
        name: $0.name,
        kind: $0.kind,
        connected: $0.connected
      )
    }
  }

  private static func activeDeviceIDs(
    in devices: [CaptureDeviceState]
  ) -> [String] {
    devices.filter(\.active).map(\.id)
  }
}

private struct CaptureDeviceIdentity: Equatable {
  let id: String
  let name: String
  let kind: CaptureDeviceKind
  let connected: Bool
}

/// Injectable inventory boundary used by the event source and unit tests.
@MainActor
protocol CaptureDeviceInventoryMonitoring: AnyObject {
  var onChange: (() -> Void)? { get set }
  var devices: [CaptureDeviceState] { get }

  func start()
  func stop()
}

/// Combines the best event source for each capture-device family.
@MainActor
private final class SystemCaptureDeviceInventoryMonitor: CaptureDeviceInventoryMonitoring {
  var onChange: (() -> Void)?

  var devices: [CaptureDeviceState] {
    cameraMonitor.devices + microphoneMonitor.devices
  }

  private let cameraMonitor: CoreMediaIOCameraInventoryMonitor
  private let microphoneMonitor: CoreAudioMicrophoneInventoryMonitor
  private var settleTask: Task<Void, Never>?
  private var started = false

  init(logger: ProcessLogger) {
    cameraMonitor = CoreMediaIOCameraInventoryMonitor(logger: logger.child("camera"))
    microphoneMonitor = CoreAudioMicrophoneInventoryMonitor(logger: logger.child("microphone"))
  }

  func start() {
    guard !started else { return }
    started = true

    cameraMonitor.onChange = { [weak self] in
      self?.handleCameraChange()
    }
    microphoneMonitor.onChange = { [weak self] in
      self?.handleChildChange()
    }

    cameraMonitor.start()
    microphoneMonitor.setCameraActive(cameraMonitor.devices.contains(where: \.active))
    microphoneMonitor.start()
  }

  func stop() {
    guard started else { return }
    started = false

    settleTask?.cancel()
    settleTask = nil
    cameraMonitor.stop()
    microphoneMonitor.stop()
    cameraMonitor.onChange = nil
    microphoneMonitor.onChange = nil
  }

  private func handleCameraChange() {
    guard started else { return }
    microphoneMonitor.setCameraActive(cameraMonitor.devices.contains(where: \.active))
    handleChildChange()
  }

  /// Publishes the native notification immediately, then verifies the combined state once more.
  ///
  /// Camera and microphone frameworks do not always settle their activity properties in the same
  /// callback turn. The delayed read is tied to a native notification and is not periodic polling.
  private func handleChildChange() {
    guard started else { return }
    onChange?()

    settleTask?.cancel()
    settleTask = Task { @MainActor [weak self] in
      do {
        try await Task.sleep(nanoseconds: 500_000_000)
      } catch {
        return
      }

      guard !Task.isCancelled, let self, self.started else { return }
      self.settleTask = nil
      self.onChange?()
    }
  }
}

/// Core Media I/O-backed camera inventory and activity observation.
@MainActor
private final class CoreMediaIOCameraInventoryMonitor: CaptureDeviceInventoryMonitoring {
  var onChange: (() -> Void)?

  var devices: [CaptureDeviceState] {
    deviceIDs.map(makeDeviceState)
  }

  private struct PropertyListener {
    let objectID: CMIOObjectID
    let address: CMIOObjectPropertyAddress
    let block: CMIOObjectPropertyListenerBlock
  }

  private let logger: ProcessLogger
  private let callbackQueue = DispatchQueue.main

  private var deviceIDs: [CMIODeviceID] = []
  private var deviceListListener: PropertyListener?
  private var runningListeners: [CMIODeviceID: PropertyListener] = [:]
  private var started = false

  init(logger: ProcessLogger) {
    self.logger = logger
  }

  func start() {
    guard !started else { return }
    started = true

    deviceListListener = addListener(
      objectID: CMIOObjectID(kCMIOObjectSystemObject),
      address: Self.deviceListAddress
    ) { [weak self] in
      self?.handleDeviceListChange()
    }

    reconcileDevices()
  }

  func stop() {
    guard started else { return }
    started = false

    if let listener = deviceListListener {
      removeListener(listener)
    }
    deviceListListener = nil

    for listener in runningListeners.values {
      removeListener(listener)
    }
    runningListeners.removeAll()
    deviceIDs.removeAll()
  }

  private func handleDeviceListChange() {
    guard started else { return }
    reconcileDevices()
    onChange?()
  }

  private func reconcileDevices() {
    let nextDeviceIDs = Self.readDeviceIDs().sorted()
    let nextDeviceSet = Set(nextDeviceIDs)

    let staleDeviceIDs = runningListeners.keys.filter { !nextDeviceSet.contains($0) }
    for deviceID in staleDeviceIDs {
      if let listener = runningListeners.removeValue(forKey: deviceID) {
        removeListener(listener)
      }
    }

    for deviceID in nextDeviceIDs where runningListeners[deviceID] == nil {
      guard Self.hasProperty(objectID: deviceID, address: Self.runningAddress) else {
        logger.debug(
          "camera does not expose running-state property",
          .field("device_id", deviceID)
        )
        continue
      }

      if let listener = addListener(
        objectID: deviceID,
        address: Self.runningAddress,
        handler: { [weak self] in
          guard let self, self.started else { return }
          self.onChange?()
        }
      ) {
        runningListeners[deviceID] = listener
      }
    }

    deviceIDs = nextDeviceIDs

    logger.debug(
      "camera inventory observers reconciled",
      .field("devices", deviceIDs.count),
      .field("activity_listeners", runningListeners.count)
    )
  }

  private func addListener(
    objectID: CMIOObjectID,
    address: CMIOObjectPropertyAddress,
    handler: @escaping @MainActor @Sendable () -> Void
  ) -> PropertyListener? {
    var mutableAddress = address
    let block: CMIOObjectPropertyListenerBlock = { _, _ in
      Task { @MainActor in
        handler()
      }
    }

    let status = CMIOObjectAddPropertyListenerBlock(
      objectID,
      &mutableAddress,
      callbackQueue,
      block
    )
    guard status == noErr else {
      logger.warn(
        "failed to subscribe Core Media I/O property",
        .field("object_id", objectID),
        .field("selector", Self.fourCharacterCode(address.mSelector)),
        .field("status", status)
      )
      return nil
    }

    return PropertyListener(
      objectID: objectID,
      address: address,
      block: block
    )
  }

  private func removeListener(_ listener: PropertyListener) {
    var address = listener.address
    let status = CMIOObjectRemovePropertyListenerBlock(
      listener.objectID,
      &address,
      callbackQueue,
      listener.block
    )
    if status != noErr {
      logger.warn(
        "failed to unsubscribe Core Media I/O property",
        .field("object_id", listener.objectID),
        .field("selector", Self.fourCharacterCode(listener.address.mSelector)),
        .field("status", status)
      )
    }
  }

  private func makeDeviceState(_ deviceID: CMIODeviceID) -> CaptureDeviceState {
    CaptureDeviceState(
      id: Self.readString(
        objectID: deviceID,
        address: Self.deviceUIDAddress
      ) ?? "coremediaio:\(deviceID)",
      name: Self.readString(
        objectID: deviceID,
        address: Self.deviceNameAddress
      ) ?? "Camera \(deviceID)",
      kind: .camera,
      connected: Self.readUInt32(
        objectID: deviceID,
        address: Self.aliveAddress,
        fallback: 1
      ) != 0,
      active: Self.readUInt32(
        objectID: deviceID,
        address: Self.runningAddress
      ) != 0
    )
  }

  private static let deviceListAddress = CMIOObjectPropertyAddress(
    mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
    mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
    mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
  )

  private static let runningAddress = CMIOObjectPropertyAddress(
    mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
    mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
    mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
  )

  private static let aliveAddress = CMIOObjectPropertyAddress(
    mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsAlive),
    mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
    mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
  )

  private static let deviceUIDAddress = CMIOObjectPropertyAddress(
    mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceUID),
    mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
    mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
  )

  private static let deviceNameAddress = CMIOObjectPropertyAddress(
    mSelector: CMIOObjectPropertySelector(kCMIOObjectPropertyName),
    mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
    mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
  )

  private static func readDeviceIDs() -> [CMIODeviceID] {
    var address = deviceListAddress
    var dataSize: UInt32 = 0
    guard
      CMIOObjectGetPropertyDataSize(
        CMIOObjectID(kCMIOObjectSystemObject),
        &address,
        0,
        nil,
        &dataSize
      ) == noErr,
      dataSize > 0
    else {
      return []
    }

    let count = Int(dataSize) / MemoryLayout<CMIODeviceID>.stride
    guard count > 0 else { return [] }

    var dataUsed: UInt32 = 0
    var result = [CMIODeviceID](repeating: 0, count: count)
    let status = result.withUnsafeMutableBytes { buffer -> OSStatus in
      guard let baseAddress = buffer.baseAddress else { return -1 }
      return CMIOObjectGetPropertyData(
        CMIOObjectID(kCMIOObjectSystemObject),
        &address,
        0,
        nil,
        dataSize,
        &dataUsed,
        baseAddress
      )
    }

    guard status == noErr else { return [] }
    let usedCount = min(Int(dataUsed) / MemoryLayout<CMIODeviceID>.stride, result.count)
    return Array(result.prefix(usedCount))
  }

  private static func hasProperty(
    objectID: CMIOObjectID,
    address: CMIOObjectPropertyAddress
  ) -> Bool {
    var address = address
    return CMIOObjectHasProperty(objectID, &address)
  }

  private static func readUInt32(
    objectID: CMIOObjectID,
    address: CMIOObjectPropertyAddress,
    fallback: UInt32 = 0
  ) -> UInt32 {
    var address = address
    var value: UInt32 = fallback
    let dataSize = UInt32(MemoryLayout<UInt32>.size)
    var dataUsed: UInt32 = 0

    guard
      CMIOObjectGetPropertyData(
        objectID,
        &address,
        0,
        nil,
        dataSize,
        &dataUsed,
        &value
      ) == noErr
    else {
      return fallback
    }

    return value
  }

  private static func readString(
    objectID: CMIOObjectID,
    address: CMIOObjectPropertyAddress
  ) -> String? {
    var address = address
    var value: CFString?
    let dataSize = UInt32(MemoryLayout<CFString?>.size)
    var dataUsed: UInt32 = 0

    let status = withUnsafeMutablePointer(to: &value) { valuePointer in
      CMIOObjectGetPropertyData(
        objectID,
        &address,
        0,
        nil,
        dataSize,
        &dataUsed,
        valuePointer
      )
    }

    guard status == noErr, let value else { return nil }
    return value as String
  }

  private static func fourCharacterCode(_ value: UInt32) -> String {
    let bytes: [UInt8] = [
      UInt8((value >> 24) & 0xff),
      UInt8((value >> 16) & 0xff),
      UInt8((value >> 8) & 0xff),
      UInt8(value & 0xff),
    ]
    return String(bytes: bytes, encoding: .macOSRoman) ?? String(value)
  }
}

struct MicrophoneActivityResolver {
  private(set) var cameraActive = false
  private(set) var deviceFallbackEnabled = true

  mutating func setCameraActive(_ active: Bool) {
    cameraActive = active
    if active {
      deviceFallbackEnabled = false
    }
  }

  mutating func resolve(processActive: Bool, deviceActive: Bool) -> Bool {
    if !cameraActive, !processActive, !deviceActive {
      deviceFallbackEnabled = true
    }

    if processActive {
      return true
    }
    if cameraActive || !deviceFallbackEnabled {
      return false
    }
    return deviceActive
  }
}

private struct MicrophoneActivityLogState: Equatable {
  let processActive: Bool
  let deviceActive: Bool
  let deviceFallbackEnabled: Bool
  let microphoneActive: Bool
}

/// Core Audio-backed microphone inventory and process-level input activity observation.
@MainActor
private final class CoreAudioMicrophoneInventoryMonitor: CaptureDeviceInventoryMonitoring {
  var onChange: (() -> Void)?

  var devices: [CaptureDeviceState] {
    let processActive = processObjectIDs.contains(where: Self.isRunningInput)
    let activeDeviceIDs = Set(inputDeviceIDs.filter(Self.isInputDeviceRunning))
    let deviceActive = !activeDeviceIDs.isEmpty
    let microphoneActive = activityResolver.resolve(
      processActive: processActive,
      deviceActive: deviceActive
    )

    let activeDeviceID: AudioDeviceID? = {
      guard microphoneActive else { return nil }
      if let activeDeviceID = activeDeviceIDs.sorted().first {
        return activeDeviceID
      }
      return Self.readAudioObjectID(
        objectID: AudioObjectID(kAudioObjectSystemObject),
        address: Self.defaultInputDeviceAddress
      ) ?? inputDeviceIDs.first
    }()

    logResolvedActivityIfChanged(
      processActive: processActive,
      deviceActive: deviceActive,
      microphoneActive: microphoneActive
    )

    return inputDeviceIDs.map { deviceID in
      makeDeviceState(deviceID, active: deviceID == activeDeviceID)
    }
  }

  private struct PropertyListener {
    let objectID: AudioObjectID
    let address: AudioObjectPropertyAddress
    let block: AudioObjectPropertyListenerBlock
  }

  private let logger: ProcessLogger
  private let callbackQueue = DispatchQueue.main

  private var inputDeviceIDs: [AudioDeviceID] = []
  private var processObjectIDs: [AudioObjectID] = []
  private var deviceListListener: PropertyListener?
  private var defaultInputDeviceListener: PropertyListener?
  private var processListListener: PropertyListener?
  private var inputDeviceActivityListeners: [AudioDeviceID: [PropertyListener]] = [:]
  private var processStateListeners: [AudioObjectID: [PropertyListener]] = [:]
  private var activityResolver = MicrophoneActivityResolver()
  private var lastLoggedActivity: MicrophoneActivityLogState?
  private var started = false

  init(logger: ProcessLogger) {
    self.logger = logger
  }

  func setCameraActive(_ active: Bool) {
    activityResolver.setCameraActive(active)
  }

  func start() {
    guard !started else { return }
    started = true

    deviceListListener = addListener(
      objectID: AudioObjectID(kAudioObjectSystemObject),
      address: Self.deviceListAddress
    ) { [weak self] in
      self?.handleDeviceListChange()
    }

    defaultInputDeviceListener = addListener(
      objectID: AudioObjectID(kAudioObjectSystemObject),
      address: Self.defaultInputDeviceAddress
    ) { [weak self] in
      self?.handleActivityWakeup()
    }

    processListListener = addListener(
      objectID: AudioObjectID(kAudioObjectSystemObject),
      address: Self.processListAddress
    ) { [weak self] in
      self?.handleProcessListChange()
    }

    reconcileInputDevices()
    reconcileProcesses()
  }

  func stop() {
    guard started else { return }
    started = false

    if let listener = deviceListListener {
      removeListener(listener)
    }
    if let listener = defaultInputDeviceListener {
      removeListener(listener)
    }
    if let listener = processListListener {
      removeListener(listener)
    }

    deviceListListener = nil
    defaultInputDeviceListener = nil
    processListListener = nil

    for listeners in inputDeviceActivityListeners.values {
      for listener in listeners {
        removeListener(listener)
      }
    }
    inputDeviceActivityListeners.removeAll()

    for listeners in processStateListeners.values {
      for listener in listeners {
        removeListener(listener)
      }
    }
    processStateListeners.removeAll()
    processObjectIDs.removeAll()
    inputDeviceIDs.removeAll()
    activityResolver = MicrophoneActivityResolver()
    lastLoggedActivity = nil
  }

  private func handleDeviceListChange() {
    guard started else { return }
    reconcileInputDevices()
    notifyActivityChange()
  }

  private func handleProcessListChange() {
    guard started else { return }
    reconcileProcesses()
    notifyActivityChange()
  }

  /// Re-reads process input state when any related Core Audio property changes.
  private func handleActivityWakeup() {
    guard started else { return }
    notifyActivityChange()
  }

  /// Re-reads the normalized state through the shared inventory monitor.
  private func notifyActivityChange() {
    onChange?()
  }

  private func reconcileInputDevices() {
    let nextInputDeviceIDs = Self.readAudioObjectIDs(
      objectID: AudioObjectID(kAudioObjectSystemObject),
      address: Self.deviceListAddress
    )
    .filter(Self.hasInputChannels)
    .sorted()
    let nextInputDeviceSet = Set(nextInputDeviceIDs)

    let staleDeviceIDs = inputDeviceActivityListeners.keys.filter {
      !nextInputDeviceSet.contains($0)
    }
    for deviceID in staleDeviceIDs {
      if let listeners = inputDeviceActivityListeners.removeValue(forKey: deviceID) {
        for listener in listeners {
          removeListener(listener)
        }
      }
    }

    for deviceID in nextInputDeviceIDs where inputDeviceActivityListeners[deviceID] == nil {
      let listeners = Self.deviceActivityAddresses(for: deviceID).compactMap { address in
        addListener(
          objectID: deviceID,
          address: address,
          handler: { [weak self] in
            self?.handleActivityWakeup()
          }
        )
      }
      if !listeners.isEmpty {
        inputDeviceActivityListeners[deviceID] = listeners
      }
    }

    inputDeviceIDs = nextInputDeviceIDs

    logger.debug(
      "microphone inventory reconciled",
      .field("devices", inputDeviceIDs.count),
      .field(
        "activity_listeners",
        inputDeviceActivityListeners.values.reduce(0) { $0 + $1.count }
      )
    )
  }

  private func reconcileProcesses() {
    let nextProcessObjectIDs = Self.readAudioObjectIDs(
      objectID: AudioObjectID(kAudioObjectSystemObject),
      address: Self.processListAddress
    )
    .sorted()
    let nextProcessSet = Set(nextProcessObjectIDs)

    let staleProcessObjectIDs = processStateListeners.keys.filter {
      !nextProcessSet.contains($0)
    }
    for processObjectID in staleProcessObjectIDs {
      if let listeners = processStateListeners.removeValue(forKey: processObjectID) {
        for listener in listeners {
          removeListener(listener, ignoringMissingObject: true)
        }
      }
    }

    for processObjectID in nextProcessObjectIDs
    where processStateListeners[processObjectID] == nil {
      let listeners = makeProcessStateListeners(processObjectID: processObjectID)
      if !listeners.isEmpty {
        processStateListeners[processObjectID] = listeners
      }
    }

    processObjectIDs = nextProcessObjectIDs

    logger.debug(
      "microphone process observers reconciled",
      .field("processes", processObjectIDs.count),
      .field(
        "activity_listeners",
        processStateListeners.values.reduce(0) { $0 + $1.count }
      ),
      .field("active_input_processes", processObjectIDs.filter(Self.isRunningInput).count)
    )
  }

  /// Observes every relevant process activity property and uses a wildcard only as a fallback.
  private func makeProcessStateListeners(
    processObjectID: AudioObjectID
  ) -> [PropertyListener] {
    var listeners: [PropertyListener] = []
    for address in Self.processActivityAddresses
    where Self.hasProperty(objectID: processObjectID, address: address) {
      if let listener = addListener(
        objectID: processObjectID,
        address: address,
        handler: { [weak self] in
          self?.handleActivityWakeup()
        }
      ) {
        listeners.append(listener)
      }
    }

    if listeners.isEmpty,
      let wildcardListener = addListener(
        objectID: processObjectID,
        address: Self.processWildcardAddress,
        handler: { [weak self] in
          self?.handleActivityWakeup()
        },
        logFailure: false
      )
    {
      listeners.append(wildcardListener)
    }

    return listeners
  }

  private func addListener(
    objectID: AudioObjectID,
    address: AudioObjectPropertyAddress,
    handler: @escaping @MainActor @Sendable () -> Void,
    logFailure: Bool = true
  ) -> PropertyListener? {
    var mutableAddress = address
    let block: AudioObjectPropertyListenerBlock = { _, _ in
      Task { @MainActor in
        handler()
      }
    }

    let status = AudioObjectAddPropertyListenerBlock(
      objectID,
      &mutableAddress,
      callbackQueue,
      block
    )
    guard status == noErr else {
      if logFailure {
        logger.warn(
          "failed to subscribe Core Audio property",
          .field("object_id", objectID),
          .field("selector", Self.fourCharacterCode(address.mSelector)),
          .field("status", status)
        )
      }
      return nil
    }

    return PropertyListener(
      objectID: objectID,
      address: address,
      block: block
    )
  }

  private func removeListener(
    _ listener: PropertyListener,
    ignoringMissingObject: Bool = false
  ) {
    var address = listener.address
    let status = AudioObjectRemovePropertyListenerBlock(
      listener.objectID,
      &address,
      callbackQueue,
      listener.block
    )
    if status != noErr,
      !(ignoringMissingObject && status == kAudioHardwareBadObjectError)
    {
      logger.warn(
        "failed to unsubscribe Core Audio property",
        .field("object_id", listener.objectID),
        .field("selector", Self.fourCharacterCode(listener.address.mSelector)),
        .field("status", status)
      )
    }
  }

  private func logResolvedActivityIfChanged(
    processActive: Bool,
    deviceActive: Bool,
    microphoneActive: Bool
  ) {
    let state = MicrophoneActivityLogState(
      processActive: processActive,
      deviceActive: deviceActive,
      deviceFallbackEnabled: activityResolver.deviceFallbackEnabled,
      microphoneActive: microphoneActive
    )
    guard state != lastLoggedActivity else { return }
    lastLoggedActivity = state

    logger.debug(
      "microphone activity resolved",
      .field("process_active", processActive),
      .field("device_active", deviceActive),
      .field("device_fallback_enabled", activityResolver.deviceFallbackEnabled),
      .field("microphone_active", microphoneActive)
    )
  }

  private func makeDeviceState(
    _ deviceID: AudioDeviceID,
    active: Bool
  ) -> CaptureDeviceState {
    CaptureDeviceState(
      id: Self.readString(
        objectID: deviceID,
        address: Self.deviceUIDAddress
      ) ?? "coreaudio:\(deviceID)",
      name: Self.readString(
        objectID: deviceID,
        address: Self.deviceNameAddress
      ) ?? "Audio Input \(deviceID)",
      kind: .microphone,
      connected: true,
      active: active
    )
  }

  private static let deviceListAddress = AudioObjectPropertyAddress(
    mSelector: kAudioHardwarePropertyDevices,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain
  )

  private static let defaultInputDeviceAddress = AudioObjectPropertyAddress(
    mSelector: kAudioHardwarePropertyDefaultInputDevice,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain
  )

  private static let processListAddress = AudioObjectPropertyAddress(
    mSelector: kAudioHardwarePropertyProcessObjectList,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain
  )

  private static let processRunningInputAddress = AudioObjectPropertyAddress(
    mSelector: kAudioProcessPropertyIsRunningInput,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain
  )

  private static let processRunningAddress = AudioObjectPropertyAddress(
    mSelector: kAudioProcessPropertyIsRunning,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain
  )

  private static let processRunningOutputAddress = AudioObjectPropertyAddress(
    mSelector: kAudioProcessPropertyIsRunningOutput,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain
  )

  private static let processDevicesAddress = AudioObjectPropertyAddress(
    mSelector: kAudioProcessPropertyDevices,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain
  )

  private static let processWildcardAddress = AudioObjectPropertyAddress(
    mSelector: kAudioObjectPropertySelectorWildcard,
    mScope: kAudioObjectPropertyScopeWildcard,
    mElement: kAudioObjectPropertyElementWildcard
  )

  private static let processActivityAddresses = [
    processRunningInputAddress,
    processRunningAddress,
    processRunningOutputAddress,
    processDevicesAddress,
  ]

  private static let inputDeviceRunningAddress = AudioObjectPropertyAddress(
    mSelector: kAudioDevicePropertyDeviceIsRunning,
    mScope: kAudioDevicePropertyScopeInput,
    mElement: kAudioObjectPropertyElementMain
  )

  private static let globalDeviceRunningAddress = AudioObjectPropertyAddress(
    mSelector: kAudioDevicePropertyDeviceIsRunning,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain
  )

  private static let inputDeviceRunningSomewhereAddress = AudioObjectPropertyAddress(
    mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
    mScope: kAudioDevicePropertyScopeInput,
    mElement: kAudioObjectPropertyElementMain
  )

  private static let globalDeviceRunningSomewhereAddress = AudioObjectPropertyAddress(
    mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain
  )

  private static let streamConfigurationAddress = AudioObjectPropertyAddress(
    mSelector: kAudioDevicePropertyStreamConfiguration,
    mScope: kAudioDevicePropertyScopeInput,
    mElement: kAudioObjectPropertyElementMain
  )

  private static let deviceUIDAddress = AudioObjectPropertyAddress(
    mSelector: kAudioDevicePropertyDeviceUID,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain
  )

  private static let deviceNameAddress = AudioObjectPropertyAddress(
    mSelector: kAudioObjectPropertyName,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain
  )

  private static func deviceActivityAddresses(
    for deviceID: AudioDeviceID
  ) -> [AudioObjectPropertyAddress] {
    [
      inputDeviceRunningAddress,
      globalDeviceRunningAddress,
      inputDeviceRunningSomewhereAddress,
      globalDeviceRunningSomewhereAddress,
    ].filter { hasProperty(objectID: deviceID, address: $0) }
  }

  private static func isInputDeviceRunning(_ deviceID: AudioDeviceID) -> Bool {
    for address in deviceActivityAddresses(for: deviceID)
    where readUInt32(objectID: deviceID, address: address) != 0 {
      return true
    }
    return false
  }

  private static func isRunningInput(_ processObjectID: AudioObjectID) -> Bool {
    readUInt32(
      objectID: processObjectID,
      address: processRunningInputAddress
    ) != 0
  }

  private static func readAudioObjectIDs(
    objectID: AudioObjectID,
    address: AudioObjectPropertyAddress
  ) -> [AudioObjectID] {
    var address = address
    var dataSize: UInt32 = 0
    guard
      AudioObjectGetPropertyDataSize(
        objectID,
        &address,
        0,
        nil,
        &dataSize
      ) == noErr,
      dataSize > 0
    else {
      return []
    }

    let count = Int(dataSize) / MemoryLayout<AudioObjectID>.stride
    guard count > 0 else { return [] }

    var result = [AudioObjectID](repeating: 0, count: count)
    let status = result.withUnsafeMutableBytes { buffer -> OSStatus in
      guard let baseAddress = buffer.baseAddress else { return -1 }
      return AudioObjectGetPropertyData(
        objectID,
        &address,
        0,
        nil,
        &dataSize,
        baseAddress
      )
    }

    guard status == noErr else { return [] }
    let usedCount = min(Int(dataSize) / MemoryLayout<AudioObjectID>.stride, result.count)
    return Array(result.prefix(usedCount))
  }

  private static func readAudioObjectID(
    objectID: AudioObjectID,
    address: AudioObjectPropertyAddress
  ) -> AudioObjectID? {
    var address = address
    var value = AudioObjectID(0)
    var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)

    guard
      AudioObjectGetPropertyData(
        objectID,
        &address,
        0,
        nil,
        &dataSize,
        &value
      ) == noErr,
      value != 0
    else {
      return nil
    }

    return value
  }

  private static func hasInputChannels(_ deviceID: AudioDeviceID) -> Bool {
    var address = streamConfigurationAddress
    var dataSize: UInt32 = 0
    guard
      AudioObjectGetPropertyDataSize(
        deviceID,
        &address,
        0,
        nil,
        &dataSize
      ) == noErr,
      dataSize >= UInt32(MemoryLayout<AudioBufferList>.size)
    else {
      return false
    }

    let storage = UnsafeMutableRawPointer.allocate(
      byteCount: Int(dataSize),
      alignment: MemoryLayout<AudioBufferList>.alignment
    )
    defer { storage.deallocate() }

    guard
      AudioObjectGetPropertyData(
        deviceID,
        &address,
        0,
        nil,
        &dataSize,
        storage
      ) == noErr
    else {
      return false
    }

    let bufferList = storage.assumingMemoryBound(to: AudioBufferList.self)
    return UnsafeMutableAudioBufferListPointer(bufferList).contains { buffer in
      buffer.mNumberChannels > 0
    }
  }

  private static func hasProperty(
    objectID: AudioObjectID,
    address: AudioObjectPropertyAddress
  ) -> Bool {
    var address = address
    return AudioObjectHasProperty(objectID, &address)
  }

  private static func readUInt32(
    objectID: AudioObjectID,
    address: AudioObjectPropertyAddress
  ) -> UInt32 {
    var address = address
    var value: UInt32 = 0
    var dataSize = UInt32(MemoryLayout<UInt32>.size)

    guard
      AudioObjectGetPropertyData(
        objectID,
        &address,
        0,
        nil,
        &dataSize,
        &value
      ) == noErr
    else {
      return 0
    }

    return value
  }

  private static func readString(
    objectID: AudioObjectID,
    address: AudioObjectPropertyAddress
  ) -> String? {
    var address = address
    var value: CFString?
    var dataSize = UInt32(MemoryLayout<CFString?>.size)

    let status = withUnsafeMutablePointer(to: &value) { valuePointer in
      AudioObjectGetPropertyData(
        objectID,
        &address,
        0,
        nil,
        &dataSize,
        valuePointer
      )
    }

    guard status == noErr, let value else { return nil }
    return value as String
  }

  private static func fourCharacterCode(_ value: UInt32) -> String {
    let bytes: [UInt8] = [
      UInt8((value >> 24) & 0xff),
      UInt8((value >> 16) & 0xff),
      UInt8((value >> 8) & 0xff),
      UInt8(value & 0xff),
    ]
    return String(bytes: bytes, encoding: .macOSRoman) ?? String(value)
  }
}
