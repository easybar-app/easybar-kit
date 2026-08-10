import EasyBarShared
import Foundation
import XCTest

@testable import EasyBarKit

final class LuaJSONTests: XCTestCase {
  func testNullAndContainerShapesRoundTrip() throws {
    let output = try runLua(
      """
      local json = dofile("Sources/EasyBarKit/Lua/easybar/json.lua")
      local value = json.decode('{"values":[1,null,3],"emptyObject":{},"emptyArray":[]}')
      assert(#value.values == 3)
      assert(value.values[2] == json.null)
      assert(json.encode(value.values) == '[1,null,3]')
      assert(json.encode(value.emptyObject) == '{}')
      assert(json.encode(value.emptyArray) == '[]')
      assert(json.encode(json.object()) == '{}')
      assert(json.encode(json.array()) == '[]')
      assert(json.is_array({}))
      assert(json.is_array({ 1, 2 }))
      assert(json.is_array(json.array()))
      assert(not json.is_array({ value = 1 }))
      assert(not json.is_array({ [2] = 1 }))
      assert(not json.is_array(json.object()))
      assert(not pcall(json.array, false))
      assert(not pcall(json.object, false))
      print("ok")
      """
    )

    XCTAssertEqual(output, "ok")
  }

  func testUnicodeSurrogatePairsDecodeToOneCodePoint() throws {
    let output = try runLua(
      """
      local json = dofile("Sources/EasyBarKit/Lua/easybar/json.lua")
      local value = json.decode([["\\uD83D\\uDE00"]])
      assert(value == "😀")
      print(value)
      """
    )

    XCTAssertEqual(output, "😀")
  }

  func testInvalidUnicodeAndNonFiniteNumbersAreRejected() throws {
    let output = try runLua(
      """
      local json = dofile("Sources/EasyBarKit/Lua/easybar/json.lua")
      assert(not pcall(json.decode, [["\\uD83D"]]))
      assert(not pcall(json.decode, [["\\uDE00"]]))
      assert(not pcall(json.encode, 0 / 0))
      assert(not pcall(json.encode, math.huge))
      assert(not pcall(json.decode, '1e9999'))
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
