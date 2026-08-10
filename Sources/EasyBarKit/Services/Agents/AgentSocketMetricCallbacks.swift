import Foundation

/// Metric callbacks shared by app-side agent socket clients.
struct AgentSocketMetricCallbacks {
  let onConnected: () -> Void
  let onDisconnected: () -> Void
  let onDecodedMessage: () -> Void
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
