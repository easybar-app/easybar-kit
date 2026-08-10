import Darwin
import EasyBarShared
import Foundation
import XCTest

@testable import EasyBarKit

final class LuaRenderIntervalTests: LuaRenderRuntimeTestCase, @unchecked Sendable {
  func testIntervalSubscriptionChangesAreReemittedAfterWidgetMutation() async throws {
    let widgetsDirectoryURL = try makeWidgetsDirectory()

    try """
    local brew

    brew = easybar.add("item", "brew", {
    	position = "right",
    	interval = 60,
    	label = "60",
    	on_interval = function()
    		brew:set({
    			label = "tick",
    		})
    	end,
    })

    brew:subscribe(easybar.events.forced, function()
    	brew:set({
    		interval = 5,
    		label = "5",
    		on_interval = function()
    			brew:set({
    				label = "tick-fast",
    			})
    		end,
    	})
    end)
    """.write(
      to: widgetsDirectoryURL.appendingPathComponent("brew.lua"),
      atomically: true,
      encoding: .utf8
    )

    let logger = ProcessLogger(
      label: "lua.interval-resubscribe.test",
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

    let initialSubscriptions = try await nextUpdate(
      from: recorder,
      matching: { update in
        update.isSubscriptions && Set(update.subscribedEvents) == ["forced", "interval_tick:brew:60"]
      }
    )
    XCTAssertEqual(Set(initialSubscriptions.subscribedEvents), ["forced", "interval_tick:brew:60"])

    try stdinPipe.fileHandleForWriting.write(
      contentsOf: Data("{\"name\":\"forced\"}\n".utf8)
    )

    let updatedSubscriptions = try await nextUpdate(
      from: recorder,
      matching: { update in
        update.isSubscriptions && Set(update.subscribedEvents) == ["forced", "interval_tick:brew:5"]
      }
    )
    XCTAssertEqual(Set(updatedSubscriptions.subscribedEvents), ["forced", "interval_tick:brew:5"])
  }

}
