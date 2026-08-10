import EasyBarShared
import Foundation

/// Coalesces concurrent version checks and caches only successful validation.
actor AeroSpaceVersionValidationCache {
  private struct Attempt {
    let id: UInt64
    let generation: UInt64
    let task: Task<Bool, Never>
  }

  private let commandRunner: any AeroSpaceCommandRunning
  private let logger: ProcessLogger
  private var successfulGeneration: UInt64?
  private var attempt: Attempt?
  private var nextAttemptID: UInt64 = 0

  init(commandRunner: any AeroSpaceCommandRunning, logger: ProcessLogger) {
    self.commandRunner = commandRunner
    self.logger = logger
  }

  func validate(generation: UInt64) async -> Bool {
    if successfulGeneration == generation {
      return true
    }
    if let attempt, attempt.generation == generation {
      return await attempt.task.value
    }

    attempt?.task.cancel()
    nextAttemptID &+= 1
    let attemptID = nextAttemptID
    let commandRunner = commandRunner
    let logger = logger
    let task = Task.detached(priority: .utility) {
      guard let output = await commandRunner.run(arguments: ["--version"]) else {
        logger.debug("aerospace version command unavailable")
        return false
      }

      do {
        try AeroSpaceVersionRequirement.validate(output: output)
        logger.debug(
          "aerospace version requirement satisfied",
          .field("minimum", AeroSpaceVersionRequirement.minimum.description)
        )
        return true
      } catch {
        logger.error(
          "aerospace version requirement failed",
          .field("minimum", AeroSpaceVersionRequirement.minimum.description),
          .field("error", error)
        )
        return false
      }
    }
    attempt = Attempt(id: attemptID, generation: generation, task: task)

    let result = await task.value
    if attempt?.id == attemptID {
      attempt = nil
      if result {
        successfulGeneration = generation
      }
    }
    return result
  }

  func cancel() {
    attempt?.task.cancel()
    attempt = nil
    successfulGeneration = nil
  }
}
