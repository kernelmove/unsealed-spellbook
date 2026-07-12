import Foundation
import Testing

@testable import UnsealedSpellbookCore

@Suite("Usage aggregation")
struct AggregationAcceptanceTests {
  @Test("Only unique events inside the requested date range are aggregated")
  func aggregatesToday() {
    let start = Date(timeIntervalSince1970: 1_783_824_000)
    let events = [
      UsageEvent(
        id: "same", provider: .claudeCode, timestamp: start.addingTimeInterval(1),
        usage: .init(input: 10, output: 2, total: 12)),
      UsageEvent(
        id: "same", provider: .claudeCode, timestamp: start.addingTimeInterval(1),
        usage: .init(input: 10, output: 2, total: 12)),
      UsageEvent(
        id: "codex", provider: .codex, timestamp: start.addingTimeInterval(2),
        usage: .init(input: 3, output: 4, total: 7)),
      UsageEvent(
        id: "old", provider: .openCode, timestamp: start.addingTimeInterval(-1),
        usage: .init(input: 100, output: 100, total: 200)),
    ]

    let snapshot = UsageAggregator.aggregate(
      events,
      interval: DateInterval(start: start, duration: 86_400)
    )

    #expect(snapshot.total.total == 19)
    #expect(snapshot.providers[.claudeCode]?.total == 12)
    #expect(snapshot.providers[.codex]?.total == 7)
    #expect(snapshot.providers[.openCode] == nil)
  }

  @Test("The newest snapshot wins when a Claude message appears in multiple files")
  func newestDuplicateWins() {
    let start = Date(timeIntervalSince1970: 1_783_824_000)
    let events = [
      UsageEvent(
        id: "same", provider: .claudeCode, timestamp: start.addingTimeInterval(2),
        usage: .init(input: 10, output: 9, total: 19)),
      UsageEvent(
        id: "same", provider: .claudeCode, timestamp: start.addingTimeInterval(1),
        usage: .init(input: 10, output: 1, total: 11)),
    ]

    let snapshot = UsageAggregator.aggregate(
      events,
      interval: DateInterval(start: start, duration: 60)
    )

    #expect(snapshot.total.total == 19)
    #expect(snapshot.eventCount == 1)
  }
}
