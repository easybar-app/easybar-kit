import Foundation

/// Connects one process logger to bounded live log subscribers on a socket transport.
public enum ProcessLogSocketSink {
  /// Installs a non-blocking live sink for one transport.
  ///
  /// Each subscriber supplies its own filter. The logger only formats records as
  /// verbose as the most detailed active subscriber requires, while the transport
  /// applies the individual filter and enqueues matching records independently.
  public static func install<Subscriber, Request, Response>(
    logger: ProcessLogger,
    transport: LineSocketServerTransport<Subscriber, Request, Response>,
    subscription: @escaping @Sendable (Subscriber) -> IPC.LogSubscription?,
    response: @escaping @Sendable (ProcessLogEvent) -> Response
  )
  where
    Subscriber: Sendable,
    Request: Decodable & Sendable,
    Response: Encodable & Sendable
  {
    logger.configureLiveSink(
      minimumLevel: { [weak transport] persistentMinimumLevel in
        guard let transport else { return nil }

        let requestedLevels = transport.subscribersSnapshot().compactMap { entry in
          subscription(entry.subscriber)?.effectiveMinimumLevel(
            default: persistentMinimumLevel
          )
        }
        return ProcessLogLevel.allCases.first { requestedLevels.contains($0) }
      },
      emit: { [weak transport] event, persistentMinimumLevel in
        guard let transport else { return }

        for entry in transport.subscribersSnapshot() {
          guard let logSubscription = subscription(entry.subscriber) else { continue }
          guard
            logSubscription.matches(
              event,
              defaultMinimumLevel: persistentMinimumLevel
            )
          else { continue }

          _ = transport.enqueue(response(event), to: entry.fd)
        }
      }
    )
  }
}
