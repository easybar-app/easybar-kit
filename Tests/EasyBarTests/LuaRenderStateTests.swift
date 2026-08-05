import Darwin
import EasyBarShared
import Foundation
import XCTest

@testable import EasyBarApp

final class LuaRenderStateTests: LuaRenderRuntimeTestCase, @unchecked Sendable {
  func testRemovingRootEmitsExplicitClearRootUpdate() async throws {
    let widgetsDirectoryURL = try makeWidgetsDirectory()

    try """
    local brew = easybar.add("item", "brew", {
    	position = "right",
    	icon = "idle",
    	label = "Idle",
    })

    brew:subscribe(easybar.events.forced, function()
    	brew:remove()
    end)
    """.write(
      to: widgetsDirectoryURL.appendingPathComponent("brew.lua"),
      atomically: true,
      encoding: .utf8
    )

    let logger = ProcessLogger(
      label: "lua.clear-root.test",
      minimumLevel: .error
    )
    let runtimeController = LuaProcessController(logger: logger)

    guard let runtimePath = runtimeController.resolvedRuntimePath() else {
      XCTFail("Missing bundled runtime.lua")
      return
    }

    let recorder = RuntimeUpdateRecorder()
    let runtime = try RuntimeProcess(
      runtimePath: runtimePath,
      widgetsDirectoryURL: widgetsDirectoryURL,
      recorder: recorder,
      decoder: decoder,
      environment: try luaRuntimeEnvironment(for: widgetsDirectoryURL),
      autoRespondToCommands: true
    )
    defer {
      runtime.stop()
    }

    let initialUpdate = try await nextTreeUpdate(
      from: recorder,
      matching: { [self] in rootNode(in: $0)?.id == "brew" }
    )
    XCTAssertEqual(rootNode(in: initialUpdate)?.text, "Idle")

    try runtime.sendHostEvent("{\"name\":\"forced\"}\n")

    let clearUpdate = try await nextUpdate(
      from: recorder,
      matching: { update in
        update.isClearRoot && update.clearRootID == "brew"
      }
    )
    XCTAssertEqual(clearUpdate.clearRootID, "brew")
  }

  func testUnsetClearsNestedProperties() async throws {
    let widgetsDirectoryURL = try makeWidgetsDirectory()

    try """
    local brew = easybar.add("item", "brew", {
    	position = "right",
    	label = {
    		string = "Idle",
    		color = "#ff0000",
    	},
    })

    brew:subscribe(easybar.events.forced, function()
    	brew:unset("label.color")
    end)
    """.write(
      to: widgetsDirectoryURL.appendingPathComponent("brew.lua"),
      atomically: true,
      encoding: .utf8
    )

    let logger = ProcessLogger(
      label: "lua.unset.test",
      minimumLevel: .error
    )
    let runtimeController = LuaProcessController(logger: logger)

    guard let runtimePath = runtimeController.resolvedRuntimePath() else {
      XCTFail("Missing bundled runtime.lua")
      return
    }

    let recorder = RuntimeUpdateRecorder()
    let runtime = try RuntimeProcess(
      runtimePath: runtimePath,
      widgetsDirectoryURL: widgetsDirectoryURL,
      recorder: recorder,
      decoder: decoder,
      environment: try luaRuntimeEnvironment(for: widgetsDirectoryURL),
      autoRespondToCommands: true
    )
    defer {
      runtime.stop()
    }

    let initialUpdate = try await nextTreeUpdate(
      from: recorder,
      matching: { [self] in rootNode(in: $0)?.id == "brew" }
    )
    XCTAssertEqual(rootNode(in: initialUpdate)?.labelColor, "#ff0000")

    try runtime.sendHostEvent("{\"name\":\"forced\"}\n")

    let updated = try await nextTreeUpdate(
      from: recorder,
      matching: { [self] in
        let root = rootNode(in: $0)
        return root?.id == "brew" && root?.labelColor == nil
      }
    )

    XCTAssertNil(rootNode(in: updated)?.labelColor)
  }

  func testInvalidBooleanValuePreventsWidgetFromLoading() async throws {
    let widgetsDirectoryURL = try makeWidgetsDirectory()

    try """
    easybar.add("item", "brew", {
    	position = "right",
    	drawing = "maybe",
    	label = "Idle",
    })
    """.write(
      to: widgetsDirectoryURL.appendingPathComponent("brew.lua"),
      atomically: true,
      encoding: .utf8
    )

    let logger = ProcessLogger(
      label: "lua.invalid-bool-strict.test",
      minimumLevel: .error
    )
    let runtimeController = LuaProcessController(logger: logger)

    guard let runtimePath = runtimeController.resolvedRuntimePath() else {
      XCTFail("Missing bundled runtime.lua")
      return
    }

    let recorder = RuntimeUpdateRecorder()
    let runtime = try RuntimeProcess(
      runtimePath: runtimePath,
      widgetsDirectoryURL: widgetsDirectoryURL,
      recorder: recorder,
      decoder: decoder,
      environment: try luaRuntimeEnvironment(for: widgetsDirectoryURL),
      autoRespondToCommands: true
    )
    defer {
      runtime.stop()
    }

    try await expectNoUpdate(
      from: recorder,
      matching: { update in
        update.isTree
      }
    )
  }

  func testPublicWidgetApiExposesJsonHelper() async throws {
    let widgetsDirectoryURL = try makeWidgetsDirectory()

    try """
    local payload = easybar.json.decode('{"name":"brew","count":2}')

    easybar.add("item", "brew", {
    	position = "right",
    	icon = payload.name,
    	label = tostring(payload.count),
    })
    """.write(
      to: widgetsDirectoryURL.appendingPathComponent("brew.lua"),
      atomically: true,
      encoding: .utf8
    )

    let logger = ProcessLogger(
      label: "lua.public-json.test",
      minimumLevel: .error
    )
    let runtimeController = LuaProcessController(logger: logger)

    guard let runtimePath = runtimeController.resolvedRuntimePath() else {
      XCTFail("Missing bundled runtime.lua")
      return
    }

    let process = Process()
    let stdinPipe = Pipe()
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    let recorder = RuntimeUpdateRecorder()
    let hostBridge = RuntimeHostBridge(
      recorder: recorder,
      decoder: decoder,
      stdinHandle: stdinPipe.fileHandleForWriting,
      asyncResponseDelayNanoseconds: 0
    )

    Self.configureLuaProcess(
      process,
      arguments: [runtimePath, widgetsDirectoryURL.path, "5", "65536", "brew.lua"]
    )
    process.standardInput = stdinPipe
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe
    process.environment = try luaRuntimeEnvironment(for: widgetsDirectoryURL)

    let stdoutObserver = RuntimeLineObserver { line in
      do {
        try await hostBridge.handleRuntimeLine(line)
      } catch {
        XCTFail("Failed handling runtime update: \(line) error=\(error)")
      }
    }
    stdoutObserver.attach(to: stdoutPipe.fileHandleForReading)

    let stderrObserver = RuntimeLineObserver { _ in }
    stderrObserver.attach(to: stderrPipe.fileHandleForReading)

    try process.run()
    defer {
      stdoutObserver.invalidate()
      stderrObserver.invalidate()

      try? stdinPipe.fileHandleForWriting.close()

      terminate(process)
    }

    let initialUpdate = try await nextTreeUpdate(
      from: recorder,
      matching: { [self] in rootNode(in: $0)?.icon == "brew" }
    )
    XCTAssertEqual(rootNode(in: initialUpdate)?.text, "2")
  }

  func testPublicWidgetApiExposesConfiguredLogDirectory() async throws {
    let widgetsDirectoryURL = try makeWidgetsDirectory()

    try """
    easybar.add("item", "brew", {
    	position = "right",
    	label = easybar.log_dir,
    })
    """.write(
      to: widgetsDirectoryURL.appendingPathComponent("brew.lua"),
      atomically: true,
      encoding: .utf8
    )

    let logger = ProcessLogger(
      label: "lua.public-log-dir.test",
      minimumLevel: .error
    )
    let runtimeController = LuaProcessController(logger: logger)

    guard let runtimePath = runtimeController.resolvedRuntimePath() else {
      XCTFail("Missing bundled runtime.lua")
      return
    }

    let recorder = RuntimeUpdateRecorder()
    var environment = try luaRuntimeEnvironment(for: widgetsDirectoryURL)
    environment[SharedEnvironmentKeys.luaLoggingDirectory] = loggingDirectoryURL.path

    let runtime = try RuntimeProcess(
      runtimePath: runtimePath,
      widgetsDirectoryURL: widgetsDirectoryURL,
      recorder: recorder,
      decoder: decoder,
      environment: environment,
      autoRespondToCommands: true
    )
    defer {
      runtime.stop()
    }

    let initialUpdate = try await nextTreeUpdate(
      from: recorder,
      matching: { [self] in rootNode(in: $0)?.id == "brew" }
    )
    XCTAssertEqual(rootNode(in: initialUpdate)?.text, loggingDirectoryURL.path)
  }

  func testPublicWidgetApiFileLoggerAppendsTailsAndTrims() async throws {
    let widgetsDirectoryURL = try makeWidgetsDirectory()

    try """
    local status = easybar.add(easybar.kind.item, "brew", {
    	position = "right",
    	label = "starting",
    })

    local ok, result = pcall(function()
    	local hostLog = easybar.log.with_prefix("[host]")
    	hostLog(easybar.level.info, "prefixed", "line")

    	local log = easybar.log.with_file("widget.log", {
    		prefix = "[test]",
    	})

    	log(easybar.level.info, "host", "line")
    	log.append("raw")
    	log.append("last")
    	log.trim(2)

    	local tail = log.tail(10):gsub(string.char(10), "|")
    	if tail == "" then
    		return "<empty>"
    	end

    	return tail
    end)

    if ok then
    	status:set({
    		label = result,
    	})
    else
    	status:set({
    		label = "error: " .. tostring(result),
    	})
    end
    """.write(
      to: widgetsDirectoryURL.appendingPathComponent("brew.lua"),
      atomically: true,
      encoding: .utf8
    )

    let logger = ProcessLogger(
      label: "lua.file-logger.test",
      minimumLevel: .error
    )
    let runtimeController = LuaProcessController(logger: logger)

    guard let runtimePath = runtimeController.resolvedRuntimePath() else {
      XCTFail("Missing bundled runtime.lua")
      return
    }

    let recorder = RuntimeUpdateRecorder()
    var environment = try luaRuntimeEnvironment(for: widgetsDirectoryURL)
    environment[SharedEnvironmentKeys.luaLoggingDirectory] = loggingDirectoryURL.path

    let runtime = try RuntimeProcess(
      runtimePath: runtimePath,
      widgetsDirectoryURL: widgetsDirectoryURL,
      recorder: recorder,
      decoder: decoder,
      environment: environment,
      autoRespondToCommands: true
    )
    defer {
      runtime.stop()
    }

    let initialUpdate = try await nextTreeUpdate(
      from: recorder,
      matching: { [self] in
        rootNode(in: $0)?.id == "brew" && rootNode(in: $0)?.text != "starting"
      }
    )
    XCTAssertEqual(rootNode(in: initialUpdate)?.text, "raw|last")

    let logURL = loggingDirectoryURL.appendingPathComponent("widget.log")
    let logContents = try String(contentsOf: logURL, encoding: .utf8)
    XCTAssertEqual(logContents, "raw\nlast\n")
  }

}
