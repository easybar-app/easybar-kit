import Darwin
import Foundation

/// Serializes access to cli activity spinner state.
actor CLIActivitySpinner {
  static let clearLine = "\r\u{001B}[2K"
  private static let frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

  private let message: String
  private let interactive: Bool
  private var animationTask: Task<Void, Never>?

  /// Creates a cli activity spinner.
  init(
    message: String,
    interactive: Bool = isatty(STDERR_FILENO) != 0
  ) {
    self.message = message
    self.interactive = interactive
  }

  /// Starts the associated service.
  func start() {
    guard interactive, animationTask == nil else { return }
    animationTask = Task { [weak self] in
      await self?.animate()
    }
  }

  /// Stops the associated service.
  func stop() async {
    guard let animationTask else { return }
    self.animationTask = nil
    animationTask.cancel()
    await animationTask.value
    Self.writeToStandardError(Self.clearLine)
  }

  /// Renders line.
  static func renderLine(frameIndex: Int, message: String) -> String {
    let frame = frames[frameIndex % frames.count]
    let sanitized = String(
      message.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
    )
    return "\r\(frame) \(sanitized)"
  }

  /// Runs the configured animation.
  private func animate() async {
    var frameIndex = 0
    while !Task.isCancelled {
      Self.writeToStandardError(Self.renderLine(frameIndex: frameIndex, message: message))
      frameIndex = (frameIndex + 1) % Self.frames.count
      do {
        try await Task.sleep(for: .milliseconds(80))
      } catch {
        return
      }
    }
  }

  /// Writes to standard error.
  private static func writeToStandardError(_ value: String) {
    let data = Data(value.utf8)
    data.withUnsafeBytes { rawBuffer in
      guard let baseAddress = rawBuffer.baseAddress else { return }
      var written = 0
      while written < data.count {
        let count = Darwin.write(
          STDERR_FILENO,
          baseAddress.advanced(by: written),
          data.count - written
        )
        if count > 0 {
          written += count
        } else if count < 0, errno == EINTR {
          continue
        } else {
          return
        }
      }
    }
  }
}
