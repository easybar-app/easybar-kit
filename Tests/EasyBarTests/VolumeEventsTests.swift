import CoreAudio
import EasyBarShared
import XCTest

@testable import EasyBarKit

@MainActor
final class VolumeEventsTests: XCTestCase {
  private final class FakeCoreAudio: @unchecked Sendable {
    struct Registration {
      let objectID: AudioObjectID
      let address: AudioObjectPropertyAddress
      let queue: DispatchQueue
      let block: AudioObjectPropertyListenerBlock
    }

    var defaultDeviceID: AudioDeviceID?
    var registrations: [Registration] = []
    var removalStatuses: [AudioObjectPropertySelector: [OSStatus]] = [:]
    var removedSelectors: [AudioObjectPropertySelector] = []

    var client: VolumeEventsCoreAudioClient {
      VolumeEventsCoreAudioClient(
        defaultOutputDeviceID: { self.defaultDeviceID },
        readMutedState: { _ in false },
        addListener: { objectID, address, queue, block in
          self.registrations.append(
            Registration(objectID: objectID, address: address, queue: queue, block: block)
          )
          return noErr
        },
        removeListener: { _, address, _, _ in
          self.removedSelectors.append(address.mSelector)
          guard var statuses = self.removalStatuses[address.mSelector], !statuses.isEmpty else {
            return noErr
          }
          let status = statuses.removeFirst()
          self.removalStatuses[address.mSelector] = statuses
          return status
        }
      )
    }

    func fireDefaultDeviceChange() {
      guard
        let registration = registrations.first(where: {
          $0.address.mSelector == kAudioHardwarePropertyDefaultOutputDevice
        })
      else {
        return XCTFail("Default-device listener was not registered")
      }

      registration.queue.sync {
        var address = registration.address
        withUnsafePointer(to: &address) {
          registration.block(1, $0)
        }
      }
    }

    func additionCount(for selector: AudioObjectPropertySelector) -> Int {
      registrations.count { $0.address.mSelector == selector }
    }

    func removalCount(for selector: AudioObjectPropertySelector) -> Int {
      removedSelectors.count { $0 == selector }
    }
  }

  func testRemovalFailuresDoNotSkipOtherListenersAndCanBeRetried() {
    let fake = FakeCoreAudio()
    fake.defaultDeviceID = 42
    let source = makeSource(coreAudio: fake.client)
    source.subscribeVolume()

    fake.removalStatuses[kAudioDevicePropertyVolumeScalar] = [
      kAudioHardwareUnspecifiedError,
      noErr,
    ]
    fake.removalStatuses[kAudioHardwarePropertyDefaultOutputDevice] = [
      kAudioHardwareUnspecifiedError,
      noErr,
    ]

    source.stopAll()
    XCTAssertEqual(fake.removalCount(for: kAudioDevicePropertyVolumeScalar), 1)
    XCTAssertEqual(fake.removalCount(for: kAudioDevicePropertyMute), 1)
    XCTAssertEqual(fake.removalCount(for: kAudioHardwarePropertyDefaultOutputDevice), 1)

    source.stopAll()
    XCTAssertEqual(fake.removalCount(for: kAudioDevicePropertyVolumeScalar), 2)
    XCTAssertEqual(fake.removalCount(for: kAudioDevicePropertyMute), 1)
    XCTAssertEqual(fake.removalCount(for: kAudioHardwarePropertyDefaultOutputDevice), 2)
  }

  func testMissingDefaultDeviceUninstallsOldListenersAndAllowsRebinding() {
    let fake = FakeCoreAudio()
    fake.defaultDeviceID = 42
    let source = makeSource(coreAudio: fake.client)
    source.subscribeVolume()

    XCTAssertEqual(fake.additionCount(for: kAudioDevicePropertyVolumeScalar), 1)
    XCTAssertEqual(fake.additionCount(for: kAudioDevicePropertyMute), 1)

    fake.defaultDeviceID = nil
    fake.fireDefaultDeviceChange()
    XCTAssertEqual(fake.removalCount(for: kAudioDevicePropertyVolumeScalar), 1)
    XCTAssertEqual(fake.removalCount(for: kAudioDevicePropertyMute), 1)

    fake.defaultDeviceID = 42
    fake.fireDefaultDeviceChange()
    XCTAssertEqual(fake.additionCount(for: kAudioDevicePropertyVolumeScalar), 2)
    XCTAssertEqual(fake.additionCount(for: kAudioDevicePropertyMute), 2)
  }

  private func makeSource(coreAudio: VolumeEventsCoreAudioClient) -> VolumeEvents {
    VolumeEvents(
      logger: ProcessLogger(label: "volume-events.tests", minimumLevel: .error),
      eventHub: EventHub(
        logger: ProcessLogger(label: "volume-events.tests", minimumLevel: .error),
        enqueueLuaEvent: { _ in }
      ),
      coreAudio: coreAudio
    )
  }
}
