import AppKit
import Darwin
import Dispatch
import EasyBarShared
import Foundation

/// Bridges terminal/process signals into normal AppKit termination.
@MainActor
final class AppSignalHandler {
  /// Logger used for signal diagnostics.
  private let logger: ProcessLogger
  /// Callback invoked when a termination signal is received.
  private let requestTermination: () -> Void

  /// Dispatch sources used to receive SIGINT/SIGTERM without a blocking wait thread.
  private var signalSources: [DispatchSourceSignal] = []
  /// Whether signal handling is currently active.
  private var started = false

  /// Creates one signal handler.
  init(
    logger: ProcessLogger,
    requestTermination: @escaping () -> Void
  ) {
    self.logger = logger
    self.requestTermination = requestTermination
  }

  /// Starts listening for termination signals.
  func start() {
    guard !started else { return }
    started = true

    signalSources = [SIGINT, SIGTERM].map { signalNumber in
      Darwin.signal(signalNumber, SIG_IGN)

      let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
      source.setEventHandler { [weak self] in
        Task { @MainActor [weak self] in
          self?.handle(signalNumber)
        }
      }
      source.resume()
      return source
    }
  }

  /// Stops listening for termination signals.
  func stop() {
    guard started else { return }
    started = false

    for source in signalSources {
      source.setEventHandler {}
      source.cancel()
    }
    signalSources.removeAll()

    Darwin.signal(SIGINT, SIG_DFL)
    Darwin.signal(SIGTERM, SIG_DFL)
  }

  /// Handles one signal source callback on the main actor.
  private func handle(_ signalNumber: Int32) {
    guard started else { return }

    switch signalNumber {
    case SIGINT:
      logger.info("received SIGINT")
    case SIGTERM:
      logger.info("received SIGTERM")
    default:
      logger.info("received termination signal", .field("signal", signalNumber))
    }

    requestTermination()
  }
}
