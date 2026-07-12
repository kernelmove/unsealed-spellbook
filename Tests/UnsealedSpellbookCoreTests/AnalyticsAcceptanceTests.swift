import Foundation
import Testing

@testable import UnsealedSpellbookCore

@Suite("Usage analytics")
struct AnalyticsAcceptanceTests {
  @Test("Dashboard periods use local calendar boundaries")
  func periodBoundaries() throws {
    let calendar = utcCalendar
    let now = date(2026, 7, 12, hour: 12)

    #expect(
      UsagePeriod.today.interval(containing: now, calendar: calendar).start == date(2026, 7, 12))
    #expect(
      UsagePeriod.thisWeek.interval(containing: now, calendar: calendar).start == date(2026, 7, 6))
    #expect(
      UsagePeriod.last7Days.interval(containing: now, calendar: calendar).start == date(2026, 7, 6))
    #expect(
      UsagePeriod.last30Days.interval(containing: now, calendar: calendar).start
        == date(2026, 6, 13))
    #expect(
      UsagePeriod.thisMonth.interval(containing: now, calendar: calendar).start == date(2026, 7, 1))
    #expect(
      UsagePeriod.thisMonth.interval(containing: now, calendar: calendar).end == date(2026, 8, 1))
  }

  @Test("Daily series includes zero-usage days")
  func completeDailySeries() {
    let events = [
      event("older", at: date(2026, 7, 10), total: 10),
      event("today", at: date(2026, 7, 12), total: 20),
    ]
    let analytics = UsageAnalytics(
      events: events, now: date(2026, 7, 12, hour: 12), calendar: utcCalendar)

    let days = analytics.dailyUsage(for: .last7Days)

    #expect(days.count == 7)
    #expect(days.map(\.usage.total) == [0, 0, 0, 0, 10, 0, 20])
  }

  @Test("Exact model and reasoning variants remain separate")
  func modelRanking() {
    let today = date(2026, 7, 12, hour: 12)
    let events = [
      event(
        "sol-xhigh",
        at: today,
        usage: .init(input: 10, output: 50, cacheRead: 40, total: 100),
        model: .init(name: "gpt-5.6-sol", variant: "xhigh")
      ),
      event(
        "sol-medium",
        at: today,
        usage: .init(input: 25, output: 25, total: 50),
        model: .init(name: "gpt-5.6-sol", variant: "medium")
      ),
      event(
        "terra-high",
        at: today,
        usage: .init(input: 20, output: 25, cacheRead: 30, total: 75),
        model: .init(name: "gpt-5.6-terra", variant: "high")
      ),
    ]
    let analytics = UsageAnalytics(events: events, now: today, calendar: utcCalendar)

    let models = analytics.modelRankings(for: .today)

    #expect(
      models.map(\.model.displayName) == [
        "gpt-5.6-sol · xhigh",
        "gpt-5.6-terra · high",
        "gpt-5.6-sol · medium",
      ])
    #expect(models.first?.cacheHitRate == 0.8)
  }

  @Test("Overview and badges are derived from all-time local usage")
  func achievements() {
    let now = date(2026, 7, 12, hour: 12)
    let events = [
      event("day-1", provider: .claudeCode, at: date(2026, 7, 10), total: 400_000_000),
      event("day-2", provider: .codex, at: date(2026, 7, 11), total: 400_000_000),
      event("day-3", provider: .openCode, at: now, total: 300_000_000),
      event("tool-4", provider: .ohMyPi, at: now, total: 1),
    ]
    let analytics = UsageAnalytics(events: events, now: now, calendar: utcCalendar)

    #expect(analytics.overview.totalTokens == 1_100_000_001)
    #expect(analytics.overview.activeDays == 3)
    #expect(analytics.overview.currentStreak == 3)
    #expect(analytics.overview.longestStreak == 3)
    #expect(analytics.achievements.first { $0.id == "three-day-streak" }?.isUnlocked == true)
    #expect(analytics.achievements.first { $0.id == "billion-tokens" }?.isUnlocked == true)
    #expect(analytics.achievements.first { $0.id == "three-tools" }?.isUnlocked == true)
    #expect(analytics.achievements.first { $0.id == "four-tools" }?.isUnlocked == false)
    #expect(analytics.achievements.first { $0.id == "trillion-tokens" }?.isUnlocked == false)
  }

  @Test("Badge catalog preserves tier counts and revised token thresholds")
  func badgeCatalog() {
    let event = event(
      "ten-billion",
      provider: .codex,
      at: date(2026, 7, 12),
      total: 10_000_000_000
    )
    let achievements = UsageAnalytics(events: [event], calendar: utcCalendar).achievements

    #expect(achievements.filter { $0.tier == .bronze }.count == 30)
    #expect(achievements.filter { $0.tier == .silver }.count == 15)
    #expect(achievements.filter { $0.tier == .gold }.count == 10)
    #expect(achievements.filter { $0.tier == .diamond }.count == 5)
    #expect(Set(achievements.map(\.id)).count == 60)
    #expect(achievements.filter { $0.availability == .active }.count == 50)
    #expect(achievements.filter { $0.availability == .comingSoon }.count == 7)
    #expect(achievements.filter { $0.availability == .hidden }.count == 3)
    #expect(achievements.filter { $0.isVisible }.count == 57)
    #expect(
      achievements.filter { $0.tier == .diamond && $0.isVisible }.map(\.id) == [
        "trillion-tokens", "million-dollar-spend",
      ])
    #expect(achievements.first { $0.id == "ten-billion-tokens" }?.tier == .gold)
    #expect(achievements.first { $0.id == "ten-billion-tokens" }?.isUnlocked == true)
    #expect(achievements.first { $0.id == "trillion-tokens" }?.isUnlocked == false)
    #expect(
      achievements.first { $0.id == "million-dollar-spend" }?.availability == .comingSoon)
  }

  @Test("Cache rate badges require enough observed input")
  func cacheSampleFloor() {
    let small = event(
      "small-cache",
      at: date(2026, 7, 12),
      usage: TokenUsage(input: 10, output: 0, cacheRead: 90, total: 100)
    )
    let large = event(
      "large-cache",
      at: date(2026, 7, 12),
      usage: TokenUsage(
        input: 60_000_000,
        output: 0,
        cacheRead: 40_000_000,
        total: 100_000_000
      )
    )

    #expect(
      UsageAnalytics(events: [small], calendar: utcCalendar).achievements.first {
        $0.id == "cache-25"
      }?.isUnlocked == false)
    #expect(
      UsageAnalytics(events: [large], calendar: utcCalendar).achievements.first {
        $0.id == "cache-25"
      }?.isUnlocked == true)
  }

  private var utcCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    calendar.firstWeekday = 2
    return calendar
  }

  private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
    utcCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
  }

  private func event(
    _ id: String,
    provider: AIProvider = .claudeCode,
    at timestamp: Date,
    total: Int
  ) -> UsageEvent {
    event(
      id, provider: provider, at: timestamp, usage: .init(input: total, output: 0, total: total))
  }

  private func event(
    _ id: String,
    provider: AIProvider = .claudeCode,
    at timestamp: Date,
    usage: TokenUsage,
    model: ModelIdentity = .unknown
  ) -> UsageEvent {
    UsageEvent(id: id, provider: provider, timestamp: timestamp, usage: usage, model: model)
  }
}
