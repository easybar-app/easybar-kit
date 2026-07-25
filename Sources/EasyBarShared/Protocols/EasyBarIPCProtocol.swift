import Foundation

/// Shared internal IPC protocol version used by EasyBar helper-process socket contracts.
///
/// This constant is public because the separate app, calendar-agent, and network-agent targets all
/// import `EasyBarShared`. It is still an internal EasyBar process-boundary contract, not a
/// user-facing or third-party API promise.
public let easyBarIPCProtocolVersion = "2"
