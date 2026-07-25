import Darwin
import EasyBarShared
import Foundation
import XCTest

final class ProcessDescriptorHardeningTests: XCTestCase {
  func testSpawnDoesNotInheritUnrelatedParentDescriptors() throws {
    var leakPipe = [Int32](repeating: -1, count: 2)
    guard pipe(&leakPipe) == 0 else {
      throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
    defer {
      if leakPipe[0] >= 0 { close(leakPipe[0]) }
      if leakPipe[1] >= 0 { close(leakPipe[1]) }
    }

    let discardedErrorFD = open("/dev/null", O_WRONLY)
    guard discardedErrorFD >= 0 else {
      throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
    defer {
      if discardedErrorFD >= 0 { close(discardedErrorFD) }
    }

    var environment = ProcessInfo.processInfo.environment
    environment["LEAK_FD"] = String(leakPipe[1])
    let command = "if eval 'printf inherited >&$LEAK_FD'; then exit 42; else exit 0; fi"
    let processIdentifier = try ProcessSpawnSupport.spawn(
      executablePath: "/bin/sh",
      arguments: ["/bin/sh", "-c", command],
      environment: environment,
      standardErrorFileDescriptor: discardedErrorFD,
      createProcessGroup: false
    )

    close(leakPipe[1])
    leakPipe[1] = -1

    let observation = ProcessWaitSupport.wait(processIdentifier: processIdentifier)
    guard case .terminated(_, let reason) = observation else {
      return XCTFail("Expected child termination, got \(observation)")
    }
    XCTAssertEqual(reason, .exited(code: 0))

    var bytes = [UInt8](repeating: 0, count: 16)
    let count = bytes.withUnsafeMutableBytes { buffer in
      Darwin.read(leakPipe[0], buffer.baseAddress, buffer.count)
    }
    XCTAssertEqual(count, 0)
  }
}
