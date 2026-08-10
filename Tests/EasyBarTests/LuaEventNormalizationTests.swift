import Foundation
import XCTest

@testable import EasyBarKit

final class LuaEventNormalizationTests: XCTestCase {
  func testCapturePayloadRemainsStructuredAndRejectsInvalidShape() throws {
    let output = try runLua(
      """
      package.path = "Sources/EasyBarKit/Lua/?.lua;Sources/EasyBarKit/Lua/?/init.lua;" .. package.path
      local events = require("easybar.events")

      local event = events.normalize_event({
          name = "capture_activity_changed",
          capture = {
              active = true,
              camera_active = true,
              microphone_active = false,
              cameras = {
                  {
                      id = "camera-1",
                      name = "Camera",
                      kind = "camera",
                      connected = true,
                      active = true,
                  },
              },
              microphones = {},
          },
      })

      assert(type(event.capture) == "table")
      assert(event.capture.active == true)
      assert(event.capture.camera_active == true)
      assert(event.capture.microphone_active == false)
      assert(event.capture.cameras[1].id == "camera-1")
      assert(not pcall(events.normalize_event, {
          name = "capture_activity_changed",
          capture = true,
      }))
      print("ok")
      """
    )

    XCTAssertEqual(output, "ok")
  }

  private func runLua(_ script: String) throws -> String {
    let process = Process()
    let stdout = Pipe()
    let stderr = Pipe()

    LuaRenderRuntimeTestCase.configureLuaProcess(process, arguments: ["-e", script])
    process.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    process.standardOutput = stdout
    process.standardError = stderr

    try process.run()
    process.waitUntilExit()

    let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
    let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
    let errorOutput = String(decoding: errorData, as: UTF8.self)

    XCTAssertEqual(process.terminationStatus, 0, errorOutput)
    return String(decoding: outputData, as: UTF8.self)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
