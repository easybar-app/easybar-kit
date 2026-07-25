import AudioToolbox
import CoreAudio
import EasyBarShared
import Foundation

private struct MicrophoneActivityLogState: Equatable {
  let processActive: Bool
  let deviceActive: Bool
  let deviceFallbackEnabled: Bool
  let microphoneActive: Bool
}

/// Core Audio-backed microphone inventory and process-level input activity observation.
@MainActor
final class CoreAudioMicrophoneInventoryMonitor: CaptureDeviceInventoryMonitoring {
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
