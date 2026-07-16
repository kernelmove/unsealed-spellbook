import AppKit
import Testing
import UnsealedSpellbookCore
import UnsealedSpellbookLanguage

@testable import UnsealedSpellbook

@Suite("Menu bar interaction")
struct StatusBarInteractionTests {
  @Test("Right click opens settings while left click keeps toggling the dashboard")
  func clickMapping() {
    #expect(StatusBarAction(eventType: .rightMouseUp) == .openSettings)
    #expect(StatusBarAction(eventType: .leftMouseUp) == .togglePopover)
  }

  @Test("Menu layout follows the selected design prototype")
  func prototypeLayout() {
    #expect(SpellbookDesign.windowSize == CGSize(width: 1040, height: 720))
    #expect(SpellbookDesign.sidebarWidth == 330)
    #expect(DashboardPage.details.title(language: .simplifiedChinese) == "概览")
  }

  @Test("Overview exposes every time range as a tab")
  @MainActor
  func periodTabs() {
    #expect(
      PeriodTabs.options.map { $0.displayName(language: .simplifiedChinese) }
        == ["今日", "本周", "近 7 天", "近 30 天", "本月"]
    )
  }

  @Test("Daily heatmap anchors the selected range in a calendar grid")
  func dailyHeatmapLayout() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    calendar.firstWeekday = 2
    let now = try #require(
      calendar.date(from: DateComponents(year: 2026, month: 7, day: 12, hour: 12))
    )
    let analytics = UsageAnalytics(
      events: [
        UsageEvent(
          id: "today",
          provider: .codex,
          timestamp: now,
          usage: TokenUsage(input: 100, output: 0, total: 100),
          model: .unknown
        )
      ],
      now: now,
      calendar: calendar
    )

    let cells = DailyMetricHeatmapLayout.cells(
      for: analytics.dailyUsage(for: .last7Days).map {
        DailyMetric(day: $0.day, value: Double($0.usage.total))
      },
      now: now,
      calendar: calendar
    )
    let today = try #require(cells.first { calendar.isDate($0.day, inSameDayAs: now) })

    #expect(
      cells.count
        == DailyMetricHeatmapLayout.columnCount * DailyMetricHeatmapLayout.rowCount
    )
    #expect(cells.count { $0.value != nil } == 7)
    #expect(today.value == 100)
    #expect(today.level == 4)
    #expect(today.showsHoverDetail)
    #expect(
      !DailyMetricHeatmapCell(
        day: now,
        value: 100,
        level: 4,
        isFuture: true
      ).showsHoverDetail
    )
    #expect(DailyMetricHeatmapLayout.intensityLevel(value: 10, maximum: 1_000) == 2)
  }
}
