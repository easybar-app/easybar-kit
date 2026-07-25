import CoreMediaIO
import EasyBarShared
import Foundation

/// Core Media I/O-backed camera inventory and activity observation.
@MainActor
final class CoreMediaIOCameraInventoryMonitor: CaptureDeviceInventoryMonitoring {
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
