import Darwin
import EasyBarShared
import Foundation

/// Actor-owned file watcher that emits debounced config change events.
///
/// The public boundary stays Swift-concurrency based through `AsyncStream`,
/// while the low-level filesystem notification uses `DispatchSourceFileSystemObject`.
/// This keeps the efficient kernel-backed watcher without leaking GCD into the
/// runtime coordinator.
actor FileWatcher {

  /// File watcher events emitted to the runtime coordinator.
  enum Event: Sendable {
    /// The watched config file or nearest ancestor changed.
    case changed
  }

  /// Resolved filesystem path currently watched by the dispatch source.
  private struct WatchTarget {
    /// Path passed to `open(..., O_EVTONLY)`.
    let path: String
    /// Human-readable target kind used in logs.
    let kind: String
  }

  /// File descriptor currently owned by the dispatch source.
  private var fileDescriptor: Int32 = -1
  /// Dispatch source observing filesystem changes.
  private var source: DispatchSourceFileSystemObject?
  /// Active stream continuation.
  private var continuation: AsyncStream<Event>.Continuation?
  /// Active debounce task.
  private var debounceTask: Task<Void, Never>?
  /// Generation used to ignore stale watcher callbacks.
  private var watcherGeneration: UInt64 = 0
  /// Queue used by the dispatch source event handler.
  private let sourceQueue = DispatchQueue(label: "easybar.file-watcher.source", qos: .utility)
  /// Logger used for file watcher diagnostics.
  private let logger: ProcessLogger

  /// Creates one config file watcher.
  init(logger: ProcessLogger) {
    self.logger = logger
  }

  /// Starts watching the given config file and returns an event stream.
  func start(configPath: String, enabled: Bool) -> AsyncStream<Event> {
    stop()
    let generation = watcherGeneration
    let (stream, continuation) = AsyncStream<Event>.makeStream()
    install(
      continuation: continuation,
      configPath: configPath,
      enabled: enabled,
      generation: generation
    )
    return stream
  }

  /// Stops the active watcher.
  func stop() {
    watcherGeneration &+= 1

    debounceTask?.cancel()
    debounceTask = nil

    continuation?.finish()
    continuation = nil

    cancelSource()
  }

  /// Installs one dispatch-source watcher when config watching is enabled.
  private func install(
    continuation: AsyncStream<Event>.Continuation,
    configPath: String,
    enabled: Bool,
    generation: UInt64
  ) {
    guard generation == watcherGeneration else {
      continuation.finish()
      return
    }

    self.continuation = continuation

    continuation.onTermination = { [weak self] _ in
      Task {
        await self?.handleTermination(generation: generation)
      }
    }

    guard enabled else {
      logger.debug("config file watcher disabled")
      return
    }

    guard let target = resolveWatchTarget(configPath: configPath) else {
      logger.warn(
        "config file watcher could not resolve watch target",
        .field("path", configPath)
      )
      return
    }

    let descriptor = open(target.path, O_EVTONLY)

    guard descriptor >= 0 else {
      logger.warn(
        "config file watcher could not open watch target",
        .field("path", target.path),
        .field("errno", errno)
      )
      return
    }

    fileDescriptor = descriptor

    let watchSource = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: descriptor,
      eventMask: [.write, .delete, .rename, .extend, .attrib, .link, .revoke],
      queue: sourceQueue
    )

    watchSource.setEventHandler { [weak self] in
      Task {
        await self?.handleFilesystemEvent(
          generation: generation,
          configPath: configPath
        )
      }
    }

    watchSource.setCancelHandler {
      close(descriptor)
    }

    source = watchSource
    watchSource.resume()

    logger.debug(
      "config file watcher started",
      .field("path", configPath),
      .field("watch_target", target.path),
      .field("watch_target_kind", target.kind)
    )
  }

  /// Handles one filesystem event from the dispatch source.
  private func handleFilesystemEvent(
    generation: UInt64,
    configPath: String
  ) {
    guard generation == watcherGeneration else { return }

    debounceTask?.cancel()
    debounceTask = Task { [weak self] in
      do {
        try await Task.sleep(for: .milliseconds(250))
      } catch {
        return
      }

      await self?.emitChangedAndRearm(
        generation: generation,
        configPath: configPath
      )
    }
  }

  /// Emits one debounced change and rearms the descriptor after replacement-style writes.
  private func emitChangedAndRearm(
    generation: UInt64,
    configPath: String
  ) {
    guard generation == watcherGeneration, let continuation else { return }

    logger.debug(
      "config file changed",
      .field("path", configPath)
    )

    continuation.yield(.changed)

    // Atomic saves replace the watched inode. Reinstalling after every debounced
    // event is inexpensive for config files and also keeps standalone watcher
    // consumers correct without relying on RuntimeCoordinator to restart it.
    cancelSource()
    install(
      continuation: continuation,
      configPath: configPath,
      enabled: true,
      generation: generation
    )
  }

  /// Handles stream termination from the consumer side.
  private func handleTermination(generation: UInt64) {
    guard generation == watcherGeneration else { return }
    stop()
  }

  /// Cancels the dispatch source and lets its cancel handler close the descriptor.
  private func cancelSource() {
    let activeSource = source
    source = nil
    fileDescriptor = -1

    activeSource?.setEventHandler {}
    activeSource?.cancel()
  }

  /// Resolves the best filesystem path to watch for one config path.
  private func resolveWatchTarget(configPath: String) -> WatchTarget? {
    let path = NSString(string: configPath).expandingTildeInPath
    let fileManager = FileManager.default

    var isDirectory = ObjCBool(false)

    if fileManager.fileExists(atPath: path, isDirectory: &isDirectory) {
      return WatchTarget(
        path: path,
        kind: isDirectory.boolValue ? "directory" : "file"
      )
    }

    let parent = URL(fileURLWithPath: path).deletingLastPathComponent().path
    isDirectory = ObjCBool(false)

    guard
      fileManager.fileExists(atPath: parent, isDirectory: &isDirectory),
      isDirectory.boolValue
    else {
      return nil
    }

    return WatchTarget(
      path: parent,
      kind: "parent_directory"
    )
  }
}
