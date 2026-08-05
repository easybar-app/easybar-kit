import Darwin
import EasyBarShared
import Foundation
import XCTest

@testable import EasyBarApp

final class LuaRenderCommandTests: LuaRenderRuntimeTestCase, @unchecked Sendable {
  func testCancelAsyncEmitsCancellationForPendingCommandToken() async throws {
    let widgetsDirectoryURL = try makeWidgetsDirectory()
    try """
    easybar.add("item", "brew", { position = "right" })
    easybar.subscribe("brew", { easybar.events.forced }, function(_)
      local token = easybar.exec_async("sleep 30", {}, function(_, _) end)
      easybar.cancel_async(token)
    end)
    """.write(
      to: widgetsDirectoryURL.appendingPathComponent("brew.lua"),
      atomically: true,
      encoding: .utf8
    )

    let runtimeController = LuaProcessController(
      logger: ProcessLogger(label: "lua.cancel-async.test", minimumLevel: .error)
    )
    let runtimePath = try XCTUnwrap(runtimeController.resolvedRuntimePath())
    let recorder = RuntimeUpdateRecorder()
    let runtime = try RuntimeProcess(
      runtimePath: runtimePath,
      widgetsDirectoryURL: widgetsDirectoryURL,
      recorder: recorder,
      decoder: decoder,
      environment: try luaRuntimeEnvironment(for: widgetsDirectoryURL),
      autoRespondToCommands: false
    )
    defer { runtime.stop() }

    try runtime.sendHostEvent("{\"name\":\"forced\"}\n")
    let request = try await nextCommandRequest(
      from: recorder,
      matching: { !$0.isSynchronous && $0.command == "sleep 30" }
    )
    let cancellation = try await nextUpdate(
      from: recorder,
      matching: { $0.commandCancelToken == request.token }
    )
    XCTAssertEqual(cancellation.commandCancelToken, request.token)
  }

  func testExecCallbackFlushesIntermediateRenderBeforeFinalMutation() async throws {
    let widgetsDirectoryURL = try makeWidgetsDirectory()

    try """
    easybar.add("item", "brew", {
    	position = "right",
    	icon = "idle",
    	label = "Idle",
    })

    easybar.subscribe("brew", { easybar.events.forced }, function(_)
    	easybar.set("brew", {
    		icon = "busy",
    		label = "Brew ...",
    	})

    	local output = easybar.exec("printf '0'", {})
    	easybar.set("brew", {
    		icon = "done",
    		label = "Brew " .. output,
    	})
    end)
    """.write(
      to: widgetsDirectoryURL.appendingPathComponent("brew.lua"),
      atomically: true,
      encoding: .utf8
    )

    let logger = ProcessLogger(
      label: "lua.render-coalescing.test",
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
      matching: { [self] in rootNode(in: $0)?.icon == "idle" }
    )
    XCTAssertEqual(rootNode(in: initialUpdate)?.text, "Idle")

    try stdinPipe.fileHandleForWriting.write(
      contentsOf: Data("{\"name\":\"forced\"}\n".utf8)
    )

    let busyUpdate = try await nextTreeUpdate(
      from: recorder,
      matching: { [self] in rootNode(in: $0)?.icon == "busy" }
    )
    XCTAssertEqual(rootNode(in: busyUpdate)?.text, "Brew ...")

    let doneUpdate = try await nextTreeUpdate(
      from: recorder,
      matching: { [self] in rootNode(in: $0)?.icon == "done" }
    )
    XCTAssertEqual(rootNode(in: doneUpdate)?.text, "Brew 0")
  }

  func testExecAsyncDeliversCompletionLaterWithoutPollingTick() async throws {
    let widgetsDirectoryURL = try makeWidgetsDirectory()

    try """
    easybar.add("item", "brew", {
    	position = "right",
    	icon = "idle",
    	label = "Idle",
    })

    easybar.subscribe("brew", { easybar.events.forced }, function(_)
    	easybar.set("brew", {
    		icon = "busy",
    		label = "Brew ...",
    	})

    	easybar.exec_async("printf '0'", {}, function(output, code)
    		easybar.set("brew", {
    			icon = "done",
    			label = "Brew " .. output .. " (" .. tostring(code) .. ")",
    		})
    	end)
    end)
    """.write(
      to: widgetsDirectoryURL.appendingPathComponent("brew.lua"),
      atomically: true,
      encoding: .utf8
    )

    let logger = ProcessLogger(
      label: "lua.exec-async.test",
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
      asyncResponseDelayNanoseconds: 50_000_000
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

    try stdinPipe.fileHandleForWriting.write(
      contentsOf: Data("{\"name\":\"forced\"}\n".utf8)
    )

    let busyUpdate = try await nextTreeUpdate(
      from: recorder,
      matching: { [self] in rootNode(in: $0)?.icon == "busy" }
    )
    XCTAssertEqual(rootNode(in: busyUpdate)?.text, "Brew ...")

    let doneUpdate = try await nextTreeUpdate(
      from: recorder,
      matching: { [self] in rootNode(in: $0)?.icon == "done" }
    )
    XCTAssertEqual(rootNode(in: doneUpdate)?.text, "Brew 0 (0)")
  }

  func testExecAndExecAsyncIncludePerCommandLimitOverrides() async throws {
    let widgetsDirectoryURL = try makeWidgetsDirectory()

    try """
    easybar.add("item", "brew", {
    	position = "right",
    	icon = "idle",
    	label = "Idle",
    })

    easybar.subscribe("brew", { easybar.events.forced }, function(_)
    	easybar.exec_async("printf 'async'", {
    		timeout_seconds = 12,
    		max_output_bytes = 4096,
    	}, function(_, _)
    	end)

    	local output, code = easybar.exec("printf 'sync'", {
    		timeout_seconds = 9.5,
    		max_output_bytes = 2048,
    	})

    	easybar.set("brew", {
    		label = output .. ":" .. tostring(code),
    	})
    end)
    """.write(
      to: widgetsDirectoryURL.appendingPathComponent("brew.lua"),
      atomically: true,
      encoding: .utf8
    )

    let logger = ProcessLogger(
      label: "lua.command-override-request.test",
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
      autoRespondToCommands: false
    )
    defer { runtime.stop() }

    try runtime.sendHostEvent("{\"name\":\"forced\"}\n")

    let asyncRequest = try await nextCommandRequest(
      from: recorder,
      matching: { !$0.isSynchronous && $0.command == "printf 'async'" }
    )
    XCTAssertEqual(asyncRequest.timeoutSeconds, 12)
    XCTAssertEqual(asyncRequest.maxOutputBytes, 4096)

    let syncRequest = try await nextCommandRequest(
      from: recorder,
      matching: { $0.isSynchronous && $0.command == "printf 'sync'" }
    )
    XCTAssertEqual(syncRequest.timeoutSeconds, 9.5)
    XCTAssertEqual(syncRequest.maxOutputBytes, 2048)
  }

  func testDefaultExecOptionsExposeConfiguredHostLimits() async throws {
    let widgetsDirectoryURL = try makeWidgetsDirectory()

    try """
    local defaults = easybar.DEFAULT_EXEC_OPTIONS

    easybar.add("item", "brew", {
    	position = "right",
    	icon = "defaults",
    	label = tostring(defaults.timeout_seconds) .. ":" .. tostring(defaults.max_output_bytes),
    })
    """.write(
      to: widgetsDirectoryURL.appendingPathComponent("brew.lua"),
      atomically: true,
      encoding: .utf8
    )

    let logger = ProcessLogger(
      label: "lua.default-exec-options.test",
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
    defer { runtime.stop() }

    let update = try await nextTreeUpdate(
      from: recorder,
      matching: { [self] in rootNode(in: $0)?.id == "brew" }
    )

    XCTAssertEqual(rootNode(in: update)?.icon, "defaults")
    XCTAssertEqual(rootNode(in: update)?.text, "5:65536")
  }

  func testUnknownExecOptionKeyPreventsWidgetFromLoading() async throws {
    let widgetsDirectoryURL = try makeWidgetsDirectory()

    try """
    local output = easybar.exec("printf '0'", {
    	timeout_second = 1,
    })

    easybar.add("item", "brew", {
    	position = "right",
    	label = output,
    })
    """.write(
      to: widgetsDirectoryURL.appendingPathComponent("brew.lua"),
      atomically: true,
      encoding: .utf8
    )

    let logger = ProcessLogger(
      label: "lua.invalid-exec-option.test",
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
    defer { runtime.stop() }

    try await expectNoUpdate(
      from: recorder,
      matching: { update in
        update.isTree
      }
    )
  }

  func testStaleCommandResponseFromPreviousRuntimeDoesNotSatisfyNewSyncCommand() async throws {
    let widgetsDirectoryURL = try makeWidgetsDirectory()

    let logger = ProcessLogger(
      label: "lua.stale-command-response.test",
      minimumLevel: .error
    )
    let runtimeController = LuaProcessController(logger: logger)

    guard let runtimePath = runtimeController.resolvedRuntimePath() else {
      XCTFail("Missing bundled runtime.lua")
      return
    }

    try """
    easybar.add("item", "brew", {
    	position = "right",
    	icon = "idle",
    	label = "Idle",
    })

    easybar.subscribe("brew", { easybar.events.forced }, function(_)
    	easybar.exec_async("printf 'old'", {}, function(output)
    		easybar.set("brew", {
    			label = output,
    		})
    	end)
    end)
    """.write(
      to: widgetsDirectoryURL.appendingPathComponent("old.lua"),
      atomically: true,
      encoding: .utf8
    )

    let oldRecorder = RuntimeUpdateRecorder()
    let oldRuntime = try RuntimeProcess(
      runtimePath: runtimePath,
      widgetsDirectoryURL: widgetsDirectoryURL,
      recorder: oldRecorder,
      decoder: decoder,
      environment: try luaRuntimeEnvironment(for: widgetsDirectoryURL),
      autoRespondToCommands: false
    )
    defer { oldRuntime.stop() }

    try oldRuntime.sendHostEvent("{\"name\":\"forced\"}\n")

    let oldRequest = try await nextCommandRequest(
      from: oldRecorder,
      matching: { !$0.isSynchronous && $0.command == "printf 'old'" }
    )

    oldRuntime.stop()
    try FileManager.default.removeItem(
      at: widgetsDirectoryURL.appendingPathComponent("old.lua")
    )

    try """
    easybar.add("item", "brew", {
    	position = "right",
    	icon = "idle",
    	label = "Idle",
    })

    easybar.subscribe("brew", { easybar.events.forced }, function(_)
    	local output = easybar.exec("printf 'fresh'", {})
    	easybar.set("brew", {
    		icon = "done",
    		label = output,
    	})
    end)
    """.write(
      to: widgetsDirectoryURL.appendingPathComponent("new.lua"),
      atomically: true,
      encoding: .utf8
    )

    let newRecorder = RuntimeUpdateRecorder()
    let newRuntime = try RuntimeProcess(
      runtimePath: runtimePath,
      widgetsDirectoryURL: widgetsDirectoryURL,
      recorder: newRecorder,
      decoder: decoder,
      environment: try luaRuntimeEnvironment(for: widgetsDirectoryURL),
      autoRespondToCommands: false
    )
    defer { newRuntime.stop() }

    try newRuntime.sendHostEvent("{\"name\":\"forced\"}\n")

    let newRequest = try await nextCommandRequest(
      from: newRecorder,
      matching: { $0.isSynchronous && $0.command == "printf 'fresh'" }
    )

    try newRuntime.sendCommandResponse(
      token: oldRequest.token,
      output: "stale",
      status: 0
    )
    try newRuntime.sendCommandResponse(
      token: newRequest.token,
      output: "fresh",
      status: 0
    )

    let doneUpdate = try await nextTreeUpdate(
      from: newRecorder,
      matching: { [self] in rootNode(in: $0)?.icon == "done" }
    )
    XCTAssertEqual(rootNode(in: doneUpdate)?.text, "fresh")
  }

}
