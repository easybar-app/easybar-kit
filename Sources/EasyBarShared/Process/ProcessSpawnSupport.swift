import Darwin
import Foundation

/// Validation and launch failures raised before or during `posix_spawn`.
public enum ProcessSpawnError: Error, Equatable, LocalizedError, Sendable {
  /// The executable name or path was empty.
  case emptyExecutable
  /// No direct executable could be found through the configured search path.
  case executableNotFound(String)
  /// A path or argument contained an embedded NUL byte.
  case embeddedNUL(field: String)
  /// An environment key was empty or contained `=`.
  case invalidEnvironmentKey(String)
  /// One POSIX launch operation failed.
  case systemCall(operation: String, code: Int32)

  /// The POSIX error code when this error originated from a system call.
  public var posixErrorCode: Int32? {
    switch self {
    case .systemCall(_, let code):
      return code
    case .executableNotFound:
      return ENOENT
    case .emptyExecutable, .embeddedNUL, .invalidEnvironmentKey:
      return EINVAL
    }
  }

  public var errorDescription: String? {
    switch self {
    case .emptyExecutable:
      return "process executable must not be empty"
    case .executableNotFound(let executable):
      return "executable not found: \(executable)"
    case .embeddedNUL(let field):
      return "\(field) contains an embedded NUL byte"
    case .invalidEnvironmentKey(let key):
      return "invalid process environment key: \(key.debugDescription)"
    case .systemCall(let operation, let code):
      let message = String(cString: strerror(code))
      return "\(operation) failed: \(message) (errno=\(code))"
    }
  }
}

/// Shared validation, executable resolution, and `posix_spawn` construction.
public enum ProcessSpawnSupport {
  private static let defaultSearchPath =
    "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"

  /// Rejects values that cannot be represented faithfully as POSIX argv and envp strings.
  public static func validate(
    executablePath: String,
    arguments: [String],
    environment: [String: String]
  ) throws {
    try validateExecutable(executablePath)

    guard !arguments.isEmpty else {
      throw ProcessSpawnError.emptyExecutable
    }

    for (index, argument) in arguments.enumerated() {
      try rejectEmbeddedNUL(argument, field: "process argument \(index)")
    }

    try validateEnvironment(environment)
  }

  /// Rejects malformed process environment keys and embedded NUL values.
  public static func validateEnvironment(_ environment: [String: String]) throws {
    for (key, value) in environment {
      guard !key.isEmpty, !key.contains("=") else {
        throw ProcessSpawnError.invalidEnvironmentKey(key)
      }

      try rejectEmbeddedNUL(key, field: "process environment key")
      try rejectEmbeddedNUL(value, field: "process environment value for \(key)")
    }
  }

  /// Resolves one direct executable through PATH without shell interpretation.
  public static func resolveExecutable(
    _ executable: String,
    environment: [String: String]
  ) throws -> String {
    guard !executable.isEmpty else {
      throw ProcessSpawnError.emptyExecutable
    }
    try rejectEmbeddedNUL(executable, field: "process executable")
    try validateEnvironment(environment)

    if executable.contains("/") {
      guard access(executable, X_OK) == 0 else {
        let code = errno
        if code == ENOENT || code == ENOTDIR {
          throw ProcessSpawnError.executableNotFound(executable)
        }
        throw ProcessSpawnError.systemCall(operation: "access", code: code)
      }
      return executable
    }

    let searchPath = environment["PATH"] ?? defaultSearchPath
    for directory in searchPath.split(separator: ":", omittingEmptySubsequences: false) {
      let base = directory.isEmpty ? "." : String(directory)
      let candidate = URL(fileURLWithPath: base).appendingPathComponent(executable).path
      if access(candidate, X_OK) == 0 {
        return candidate
      }
    }

    throw ProcessSpawnError.executableNotFound(executable)
  }

  /// Spawns one process, optionally redirecting stdout and stderr, in a dedicated process group.
  @discardableResult
  public static func spawn(
    executablePath: String,
    arguments: [String],
    environment: [String: String],
    standardOutputFileDescriptor: Int32? = nil,
    standardErrorFileDescriptor: Int32? = nil,
    closeFileDescriptors: [Int32] = [],
    createProcessGroup: Bool = true
  ) throws -> pid_t {
    try validate(
      executablePath: executablePath,
      arguments: arguments,
      environment: environment
    )

    var fileActions: posix_spawn_file_actions_t?
    var attributes: posix_spawnattr_t?

    try initializeFileActions(&fileActions)
    defer {
      if fileActions != nil {
        posix_spawn_file_actions_destroy(&fileActions)
      }
    }

    try initializeSpawnAttributes(&attributes)
    defer {
      if attributes != nil {
        posix_spawnattr_destroy(&attributes)
      }
    }

    try addInheritAction(fileActions: &fileActions, fileDescriptor: STDIN_FILENO)
    if standardOutputFileDescriptor == nil {
      try addInheritAction(fileActions: &fileActions, fileDescriptor: STDOUT_FILENO)
    }
    if standardErrorFileDescriptor == nil {
      try addInheritAction(fileActions: &fileActions, fileDescriptor: STDERR_FILENO)
    }

    if let standardOutputFileDescriptor {
      try addDup2Action(
        fileActions: &fileActions,
        sourceFileDescriptor: standardOutputFileDescriptor,
        destinationFileDescriptor: STDOUT_FILENO
      )
    }

    if let standardErrorFileDescriptor {
      try addDup2Action(
        fileActions: &fileActions,
        sourceFileDescriptor: standardErrorFileDescriptor,
        destinationFileDescriptor: STDERR_FILENO
      )
    }

    var childCloseFileDescriptors = Set(closeFileDescriptors.filter { $0 >= 0 })
    if let standardOutputFileDescriptor, standardOutputFileDescriptor != STDOUT_FILENO {
      childCloseFileDescriptors.insert(standardOutputFileDescriptor)
    }
    if let standardErrorFileDescriptor, standardErrorFileDescriptor != STDERR_FILENO {
      childCloseFileDescriptors.insert(standardErrorFileDescriptor)
    }

    for fileDescriptor in childCloseFileDescriptors.sorted() {
      try addCloseAction(fileActions: &fileActions, fileDescriptor: fileDescriptor)
    }

    try configureSpawnAttributes(
      attributes: &attributes,
      createProcessGroup: createProcessGroup
    )

    let argv = try makeCStringVector(arguments)
    defer { freeCStringVector(argv) }

    let flattenedEnvironment = environment.map { "\($0.key)=\($0.value)" }.sorted()
    let envp = try makeCStringVector(flattenedEnvironment)
    defer { freeCStringVector(envp) }

    var pid: pid_t = 0
    let result = executablePath.withCString { path in
      posix_spawn(&pid, path, &fileActions, &attributes, argv, envp)
    }

    guard result == 0 else {
      throw ProcessSpawnError.systemCall(operation: "posix_spawn", code: result)
    }

    return pid
  }

  /// Initializes one `posix_spawn_file_actions_t`.
  private static func initializeFileActions(
    _ fileActions: inout posix_spawn_file_actions_t?
  ) throws {
    fileActions = nil
    let result = posix_spawn_file_actions_init(&fileActions)
    guard result == 0 else {
      throw ProcessSpawnError.systemCall(
        operation: "posix_spawn_file_actions_init",
        code: result
      )
    }
  }

  /// Initializes one `posix_spawnattr_t`.
  private static func initializeSpawnAttributes(
    _ attributes: inout posix_spawnattr_t?
  ) throws {
    attributes = nil
    let result = posix_spawnattr_init(&attributes)
    guard result == 0 else {
      throw ProcessSpawnError.systemCall(operation: "posix_spawnattr_init", code: result)
    }
  }

  /// Closes unrelated parent descriptors and optionally creates a dedicated process group.
  private static func configureSpawnAttributes(
    attributes: inout posix_spawnattr_t?,
    createProcessGroup: Bool
  ) throws {
    var flags = Int16(POSIX_SPAWN_CLOEXEC_DEFAULT)
    if createProcessGroup {
      flags |= Int16(POSIX_SPAWN_SETPGROUP)
    }

    let flagsResult = posix_spawnattr_setflags(&attributes, flags)
    guard flagsResult == 0 else {
      throw ProcessSpawnError.systemCall(
        operation: "posix_spawnattr_setflags",
        code: flagsResult
      )
    }

    guard createProcessGroup else { return }

    let groupResult = posix_spawnattr_setpgroup(&attributes, 0)
    guard groupResult == 0 else {
      throw ProcessSpawnError.systemCall(
        operation: "posix_spawnattr_setpgroup",
        code: groupResult
      )
    }
  }

  /// Adds one child `dup2` action, preserving an already-matching descriptor explicitly.
  private static func addDup2Action(
    fileActions: inout posix_spawn_file_actions_t?,
    sourceFileDescriptor: Int32,
    destinationFileDescriptor: Int32
  ) throws {
    if sourceFileDescriptor == destinationFileDescriptor {
      try addInheritAction(
        fileActions: &fileActions,
        fileDescriptor: destinationFileDescriptor
      )
      return
    }

    let result = posix_spawn_file_actions_adddup2(
      &fileActions,
      sourceFileDescriptor,
      destinationFileDescriptor
    )
    guard result == 0 else {
      throw ProcessSpawnError.systemCall(
        operation: "posix_spawn_file_actions_adddup2",
        code: result
      )
    }
  }

  /// Marks one descriptor as intentionally inherited under the close-by-default policy.
  private static func addInheritAction(
    fileActions: inout posix_spawn_file_actions_t?,
    fileDescriptor: Int32
  ) throws {
    let result = posix_spawn_file_actions_addinherit_np(&fileActions, fileDescriptor)
    guard result == 0 else {
      throw ProcessSpawnError.systemCall(
        operation: "posix_spawn_file_actions_addinherit_np",
        code: result
      )
    }
  }

  /// Adds one child close action.
  private static func addCloseAction(
    fileActions: inout posix_spawn_file_actions_t?,
    fileDescriptor: Int32
  ) throws {
    let result = posix_spawn_file_actions_addclose(&fileActions, fileDescriptor)
    guard result == 0 else {
      throw ProcessSpawnError.systemCall(
        operation: "posix_spawn_file_actions_addclose",
        code: result
      )
    }
  }

  /// Creates one null-terminated C string vector.
  private static func makeCStringVector(
    _ values: [String]
  ) throws -> UnsafeMutablePointer<UnsafeMutablePointer<CChar>?> {
    let buffer = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>.allocate(
      capacity: values.count + 1
    )
    buffer.initialize(repeating: nil, count: values.count + 1)

    for (index, value) in values.enumerated() {
      guard let duplicated = strdup(value) else {
        freeCStringVector(buffer)
        throw ProcessSpawnError.systemCall(operation: "strdup", code: ENOMEM)
      }
      buffer[index] = duplicated
    }

    return buffer
  }

  /// Frees one C string vector allocated by `makeCStringVector`.
  private static func freeCStringVector(
    _ vector: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>
  ) {
    var index = 0
    while let value = vector[index] {
      free(value)
      index += 1
    }
    vector.deallocate()
  }

  /// Rejects one value containing an embedded C-string terminator.
  private static func rejectEmbeddedNUL(_ value: String, field: String) throws {
    guard !value.utf8.contains(0) else {
      throw ProcessSpawnError.embeddedNUL(field: field)
    }
  }

  /// Validates one executable path.
  private static func validateExecutable(_ executablePath: String) throws {
    guard !executablePath.isEmpty else {
      throw ProcessSpawnError.emptyExecutable
    }
    try rejectEmbeddedNUL(executablePath, field: "process executable path")
  }
}
