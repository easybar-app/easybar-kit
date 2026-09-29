import Foundation

/// Metric callbacks shared by app-side agent socket clients.
struct AgentSocketMetricCallbacks {
  /// The on connected for this agent socket metric callbacks.
  let onConnected: () -> Void
  /// The on disconnected for this agent socket metric callbacks.
  let onDisconnected: () -> Void
  /// The on decoded message for this agent socket metric callbacks.
  let onDecodedMessage: () -> Void
  /// The on decode error for this agent socket metric callbacks.
  let onDecodeError: () -> Void

  /// Builds callbacks that record lifecycle and message events for one agent stream.
  static func recording(
    _ agent: MetricsCoordinator.AgentKey,
    coordinator: MetricsCoordinator
  ) -> AgentSocketMetricCallbacks {
    AgentSocketMetricCallbacks(
      onConnected: {
        Task {
          await coordinator.recordAgentConnected(agent)
        }
      },
      onDisconnected: {
        Task {
          await coordinator.recordAgentDisconnected(agent)
        }
      },
      onDecodedMessage: {
        Task {
          await coordinator.recordAgentMessage(agent)
        }
      },
      onDecodeError: {
        Task {
          await coordinator.recordAgentDecodeError(agent)
        }
      }
    )
  }
}
