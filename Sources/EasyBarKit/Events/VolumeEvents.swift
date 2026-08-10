import CoreAudio
import EasyBarShared
import Foundation

/// Observes CoreAudio output volume and mute changes.
final class VolumeEvents: @unchecked Sendable {
  private struct DeviceListener {
    let deviceID: AudioDeviceID
    let address: AudioObjectPropertyAddress
    let label: String
    let block: AudioObjectPropertyListenerBlock
  }

  /// Logger used for volume diagnostics.
  private let logger: ProcessLogger
  private let eventHub: EventHub
  private let coreAudio: VolumeEventsCoreAudioClient

  /// Serializes CoreAudio callbacks and mutable listener state.
  private let stateQueue = DispatchQueue(label: "io.github.gi8lino.easybar.volume-events")
  /// Marks execution that is already isolated on `stateQueue`.
  private let stateQueueKey = DispatchSpecificKey<Void>()

  /// Current default output device id.
  private var currentDeviceID: AudioDeviceID?
  /// Whether volume observation is active.
  private var isSubscribed = false

  /// Listener for default output device changes.
  private var defaultDeviceListener: AudioObjectPropertyListenerBlock?
  /// Per-device listeners, including failed removals retained for later retry.
  private var deviceListeners: [DeviceListener] = []

  /// Last emitted mute state.
  private var lastMutedState: Bool?

  /// Creates one volume event source.
  init(
    logger: ProcessLogger,
    eventHub: EventHub,
    coreAudio: VolumeEventsCoreAudioClient = .system
  ) {
    self.logger = logger
    self.eventHub = eventHub
    self.coreAudio = coreAudio
    stateQueue.setSpecific(key: stateQueueKey, value: ())
  }

  /// Starts observation for output-device, volume, and mute changes.
  func subscribeVolume() {
    performStateMutation {
      guard !isSubscribed else { return }

      isSubscribed = true
      installDefaultOutputDeviceListener()
      refreshDeviceSubscription()

      logger.debug("subscribed volume_change")
      logger.debug("subscribed mute_change")
    }
  }

  /// Stops observation for output-device, volume, and mute changes.
  func unsubscribeVolume() {
    stopAll()
  }

  /// Stops all active audio listeners and clears cached device state.
  func stopAll() {
    performStateMutation {
      uninstallDeviceListeners()
      uninstallDefaultOutputDeviceListener()

      currentDeviceID = nil
      isSubscribed = false
      lastMutedState = nil
    }
  }

  /// Runs one mutable-state operation on the dedicated CoreAudio state queue.
  private func performStateMutation(_ body: () -> Void) {
    if DispatchQueue.getSpecific(key: stateQueueKey) != nil {
      body()
      return
    }

    stateQueue.sync(execute: body)
  }

  /// Starts listening for default output device changes.
  private func installDefaultOutputDeviceListener() {
    guard defaultDeviceListener == nil else { return }
    let eventHub = eventHub

    let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
      self?.refreshDeviceSubscription()

      Task {
        await eventHub.emit(.volumeChange)
      }
    }

    let status = addListener(
      objectID: AudioObjectID(kAudioObjectSystemObject),
      address: defaultOutputDeviceAddress(),
      block: block
    )

    guard status == noErr else {
      logger.debug(
        "failed to subscribe default output device changes",
        .field("status", status),
      )
      return
    }

    defaultDeviceListener = block
  }

  /// Removes the default output device listener.
  private func uninstallDefaultOutputDeviceListener() {
    guard let block = defaultDeviceListener else { return }

    let status = removeListener(
      objectID: AudioObjectID(kAudioObjectSystemObject),
      address: defaultOutputDeviceAddress(),
      block: block
    )

    guard status == noErr else {
      logger.debug(
        "failed to remove default output device listener",
        .field("status", status),
      )
      return
    }

    defaultDeviceListener = nil
  }

  /// Rebinds per-device listeners to the current default output device.
  private func refreshDeviceSubscription() {
    let newDeviceID = defaultOutputDeviceID()

    guard let newDeviceID else {
      uninstallDeviceListeners()
      currentDeviceID = nil
      lastMutedState = nil
      logger.debug("no default output device found")
      return
    }

    if currentDeviceID == newDeviceID {
      return
    }

    uninstallDeviceListeners()
    currentDeviceID = newDeviceID
    lastMutedState = readMutedState(for: newDeviceID)
    installDeviceListeners()
    let muted = lastMutedState ?? false
    let eventHub = eventHub

    Task {
      await eventHub.emit(.volumeChange)
      await eventHub.emit(.app(.muteChange, muted: muted))
    }
  }

  /// Starts volume and mute listeners for the current output device.
  private func installDeviceListeners() {
    guard let deviceID = currentDeviceID else { return }
    let eventHub = eventHub

    if !hasDeviceListener(deviceID: deviceID, selector: kAudioDevicePropertyVolumeScalar) {
      let volumeBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        guard let self else { return }
        self.performStateMutation {
          guard self.currentDeviceID == deviceID else { return }
          Task {
            await eventHub.emit(.volumeChange)
          }
        }
      }

      let address = volumeAddress()
      let volumeStatus = addListener(
        objectID: deviceID,
        address: address,
        block: volumeBlock
      )

      if volumeStatus == noErr {
        deviceListeners.append(
          DeviceListener(
            deviceID: deviceID,
            address: address,
            label: "volume",
            block: volumeBlock
          )
        )
      } else {
        logger.debug(
          "failed to subscribe volume listener",
          .field("status", volumeStatus),
        )
      }
    }

    guard !hasDeviceListener(deviceID: deviceID, selector: kAudioDevicePropertyMute) else {
      return
    }

    let muteBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
      guard let self else { return }
      self.performStateMutation {
        guard self.currentDeviceID == deviceID else { return }

        Task {
          await eventHub.emit(.volumeChange)
        }

        let muted = self.readMutedState(for: deviceID)
        if self.lastMutedState != muted {
          self.lastMutedState = muted

          Task {
            await eventHub.emit(.app(.muteChange, muted: muted))
          }
        }
      }
    }

    let address = muteAddress()
    let muteStatus = addListener(
      objectID: deviceID,
      address: address,
      block: muteBlock
    )

    if muteStatus == noErr {
      deviceListeners.append(
        DeviceListener(
          deviceID: deviceID,
          address: address,
          label: "mute",
          block: muteBlock
        )
      )
    } else {
      logger.debug(
        "mute listener unavailable on current output device",
        .field("status", muteStatus),
      )
    }
  }

  /// Removes all registered device listeners and retains failures for a later retry.
  private func uninstallDeviceListeners() {
    var failedRemovals: [DeviceListener] = []
    for listener in deviceListeners {
      let status = removeListener(
        objectID: listener.deviceID,
        address: listener.address,
        block: listener.block
      )

      if status != noErr,
        status != kAudioHardwareBadObjectError,
        status != kAudioHardwareBadDeviceError
      {
        logger.debug(
          "failed to remove \(listener.label) listener",
          .field("status", status),
        )
        failedRemovals.append(listener)
      }
    }
    deviceListeners = failedRemovals
  }

  /// Returns whether a listener is already registered for one device property.
  private func hasDeviceListener(
    deviceID: AudioDeviceID,
    selector: AudioObjectPropertySelector
  ) -> Bool {
    deviceListeners.contains {
      $0.deviceID == deviceID && $0.address.mSelector == selector
    }
  }

  /// Returns the current default output device id.
  private func defaultOutputDeviceID() -> AudioDeviceID? {
    coreAudio.defaultOutputDeviceID()
  }

  /// Returns the current mute state for one output device.
  private func readMutedState(for deviceID: AudioDeviceID) -> Bool {
    coreAudio.readMutedState(deviceID)
  }

  /// Returns the CoreAudio address for the default output device property.
  private func defaultOutputDeviceAddress() -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultOutputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
  }

  /// Returns the CoreAudio address for output volume.
  private func volumeAddress() -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyVolumeScalar,
      mScope: kAudioDevicePropertyScopeOutput,
      mElement: kAudioObjectPropertyElementMain
    )
  }

  /// Returns the CoreAudio address for output mute state.
  private func muteAddress() -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyMute,
      mScope: kAudioDevicePropertyScopeOutput,
      mElement: kAudioObjectPropertyElementMain
    )
  }

  /// Installs one property listener block on one audio object.
  private func addListener(
    objectID: AudioObjectID,
    address: AudioObjectPropertyAddress,
    block: @escaping AudioObjectPropertyListenerBlock
  ) -> OSStatus {
    coreAudio.addListener(objectID, address, stateQueue, block)
  }

  /// Removes one property listener block from one audio object.
  private func removeListener(
    objectID: AudioObjectID,
    address: AudioObjectPropertyAddress,
    block: @escaping AudioObjectPropertyListenerBlock
  ) -> OSStatus {
    coreAudio.removeListener(objectID, address, stateQueue, block)
  }
}
