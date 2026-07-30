import Foundation

/// Commands accepted by the network-agent socket.
public enum NetworkAgentCommand: String, Codable, Sendable {
  case ping
  case version
  case fetch
  case subscribe
  case logs
  case restart
}

/// Stable wire-level error codes returned by the network agent.
public enum NetworkAgentErrorCode: String, Codable, Equatable, Sendable {
  case permissionDenied = "permission_denied"
  case missingFields = "missing_fields"
  case providerUnavailable = "provider_unavailable"
  case unknown = "unknown"
}
