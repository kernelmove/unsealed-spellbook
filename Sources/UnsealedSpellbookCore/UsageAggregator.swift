import Foundation

public enum UsageAggregator {
  public static func uniqueEvents(
    _ events: [UsageEvent],
    interval: DateInterval = DateInterval(start: .distantPast, end: .distantFuture)
  ) -> [UsageEvent] {
    var latest: [EventKey: UsageEvent] = [:]

    for event in events
    where event.timestamp >= interval.start && event.timestamp < interval.end {
      let key = EventKey(provider: event.provider, id: event.id)
      guard let current = latest[key] else {
        latest[key] = event
        continue
      }
      if event.timestamp > current.timestamp
        || (event.timestamp == current.timestamp && event.usage.total >= current.usage.total)
      {
        latest[key] = event
      }
    }

    return latest.values.sorted { $0.timestamp < $1.timestamp }
  }

  public static func aggregate(_ events: [UsageEvent], interval: DateInterval) -> UsageSnapshot {
    let unique = uniqueEvents(events, interval: interval)
    var providers: [AIProvider: TokenUsage] = [:]
    var total = TokenUsage.zero
    for event in unique {
      providers[event.provider, default: .zero] =
        providers[event.provider, default: .zero] + event.usage
      total = total + event.usage
    }

    return UsageSnapshot(
      interval: interval,
      providers: providers,
      total: total,
      eventCount: unique.count
    )
  }

  private struct EventKey: Hashable {
    let provider: AIProvider
    let id: String
  }
}
