import Foundation

public enum UsagePeriod: String, CaseIterable, Sendable {
  case today
  case thisWeek
  case last7Days
  case last30Days
  case thisMonth

  public func interval(containing now: Date, calendar: Calendar) -> DateInterval {
    let today = calendar.startOfDay(for: now)
    let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!

    switch self {
    case .today:
      return DateInterval(start: today, end: tomorrow)
    case .thisWeek:
      return calendar.dateInterval(of: .weekOfYear, for: now)!
    case .last7Days:
      return DateInterval(
        start: calendar.date(byAdding: .day, value: -6, to: today)!,
        end: tomorrow
      )
    case .last30Days:
      return DateInterval(
        start: calendar.date(byAdding: .day, value: -29, to: today)!,
        end: tomorrow
      )
    case .thisMonth:
      return calendar.dateInterval(of: .month, for: now)!
    }
  }
}

public struct DailyUsage: Identifiable, Sendable {
  public let day: Date
  public let usage: TokenUsage
  public var id: Date { day }
}

public struct ModelUsageSummary: Identifiable, Sendable {
  public let model: ModelIdentity
  public let usage: TokenUsage
  public let recordCount: Int
  public var id: ModelIdentity { model }
  public var cacheHitRate: Double { usage.cacheHitRate }
}

public struct UsageOverview: Sendable {
  public let totalTokens: Int
  public let activeDays: Int
  public let currentStreak: Int
  public let longestStreak: Int
  public let cacheHitRate: Double
  public let providerCount: Int
  public let modelCount: Int
}

public enum BadgeTier: String, Sendable {
  case bronze
  case silver
  case gold
  case diamond
}

public enum AchievementAvailability: String, Sendable {
  case active
  case comingSoon
  case hidden
}

public struct Achievement: Identifiable, Sendable {
  public let id: String
  public let title: String
  public let detail: String
  public let systemImage: String
  public let tier: BadgeTier
  public let progress: Double
  public let progressLabel: String
  public let availability: AchievementAvailability
  public let criteriaVersion: Int

  public var isUnlocked: Bool { availability == .active && progress >= 1 }
  public var isVisible: Bool { availability != .hidden }
}

public struct UsageAnalytics: Sendable {
  public let events: [UsageEvent]
  public let now: Date
  public let calendar: Calendar
  private let metrics: AchievementMetrics

  public init(events: [UsageEvent], now: Date = Date(), calendar: Calendar = .current) {
    let uniqueEvents = UsageAggregator.uniqueEvents(events)
    self.events = uniqueEvents
    self.now = now
    self.calendar = calendar
    self.metrics = Self.makeMetrics(events: uniqueEvents, now: now, calendar: calendar)
  }

  public func snapshot(
    for period: UsagePeriod,
    provider: AIProvider? = nil
  ) -> UsageSnapshot {
    let selected = provider.map { wanted in events.filter { $0.provider == wanted } } ?? events
    return UsageAggregator.aggregate(
      selected,
      interval: period.interval(containing: now, calendar: calendar)
    )
  }

  public func dailyUsage(
    for period: UsagePeriod,
    provider: AIProvider? = nil
  ) -> [DailyUsage] {
    let interval = period.interval(containing: now, calendar: calendar)
    let selected = events.filter {
      $0.timestamp >= interval.start && $0.timestamp < interval.end
        && (provider == nil || $0.provider == provider)
    }
    var totals: [Date: TokenUsage] = [:]
    for event in selected {
      let day = calendar.startOfDay(for: event.timestamp)
      totals[day, default: .zero] = totals[day, default: .zero] + event.usage
    }

    var result: [DailyUsage] = []
    var day = calendar.startOfDay(for: interval.start)
    while day < interval.end {
      result.append(DailyUsage(day: day, usage: totals[day] ?? .zero))
      day = calendar.date(byAdding: .day, value: 1, to: day)!
    }
    return result
  }

  public func modelRankings(
    for period: UsagePeriod,
    provider: AIProvider? = nil
  ) -> [ModelUsageSummary] {
    let interval = period.interval(containing: now, calendar: calendar)
    var grouped: [ModelIdentity: (usage: TokenUsage, records: Int)] = [:]

    for event in events
    where event.timestamp >= interval.start && event.timestamp < interval.end
      && (provider == nil || event.provider == provider)
    {
      let current = grouped[event.model] ?? (.zero, 0)
      grouped[event.model] = (current.usage + event.usage, current.records + 1)
    }

    return grouped.map { model, value in
      ModelUsageSummary(model: model, usage: value.usage, recordCount: value.records)
    }.sorted {
      if $0.usage.total == $1.usage.total {
        return $0.model.displayName < $1.model.displayName
      }
      return $0.usage.total > $1.usage.total
    }
  }

  public var overview: UsageOverview {
    UsageOverview(
      totalTokens: metrics.total.total,
      activeDays: metrics.activeDays,
      currentStreak: metrics.currentStreak,
      longestStreak: metrics.longestStreak,
      cacheHitRate: metrics.total.cacheHitRate,
      providerCount: metrics.providerTotals.count,
      modelCount: metrics.modelTotals.count
    )
  }

  public var achievements: [Achievement] {
    bronzeAchievements + silverAchievements + goldAchievements + diamondAchievements
  }

  private var bronzeAchievements: [Achievement] {
    [
      achievement(
        "first-spell", "初次施法", "产生第一条有效用量记录", "sparkles", .bronze, metrics.recordCount, 1),
      achievement(
        "ten-million-tokens", "千万起步", "累计消耗 10M Token", "book.closed", .bronze, metrics.total.total,
        10_000_000),
      achievement(
        "100m-tokens", "亿级入门", "累计消耗 100M Token", "books.vertical", .bronze, metrics.total.total,
        100_000_000),
      achievement(
        "five-hundred-million-tokens", "五亿卷宗", "累计消耗 500M Token", "text.book.closed", .bronze,
        metrics.total.total, 500_000_000),
      achievement(
        "hundred-million-input", "输入洪流", "累计使用 100M 非缓存输入 Token", "arrow.down.circle", .bronze,
        metrics.total.input, 100_000_000),
      achievement(
        "hundred-million-output", "输出成章", "累计产生 100M 输出 Token", "arrow.up.circle", .bronze,
        metrics.total.output, 100_000_000),
      achievement(
        "fifty-million-reasoning", "深思初成", "累计产生 50M 推理 Token", "brain.head.profile", .bronze,
        metrics.total.reasoning, 50_000_000),
      achievement(
        "hundred-million-cache-read", "缓存拾光", "累计读取 100M 缓存 Token", "externaldrive", .bronze,
        metrics.total.cacheRead, 100_000_000),
      achievement(
        "daily-hundred-million", "单日破亿", "任意自然日消耗 100M Token", "chart.bar.fill", .bronze,
        metrics.maxDailyTokens, 100_000_000),
      achievement(
        "five-high-days", "五日高能", "有 5 天分别消耗至少 100M Token", "calendar.badge.plus", .bronze,
        metrics.days(atLeast: 100_000_000), 5),
      achievement(
        "three-day-streak", "三日连击", "最长连续活跃 3 天", "flame", .bronze, metrics.longestStreak, 3),
      achievement(
        "seven-day-streak", "七日不辍", "最长连续活跃 7 天", "7.circle", .bronze, metrics.longestStreak, 7),
      achievement(
        "fourteen-active-days", "双周旅人", "累计活跃 14 天", "calendar", .bronze, metrics.activeDays, 14),
      achievement(
        "thirty-active-days", "月度学徒", "累计活跃 30 天", "calendar", .bronze, metrics.activeDays, 30),
      achievement(
        "sixty-active-days", "双月同行", "累计活跃 60 天", "calendar", .bronze, metrics.activeDays, 60),
      achievement(
        "four-active-weeks", "跨周行者", "在 4 个不同自然周产生用量", "calendar.badge.clock", .bronze,
        metrics.activeWeeks, 4),
      achievement(
        "four-active-months", "四月留痕", "在 4 个不同自然月产生用量", "calendar.badge.checkmark", .bronze,
        metrics.activeMonths, 4),
      achievement(
        "ten-stable-days", "十日稳定", "有 10 天分别消耗至少 100M Token", "calendar.circle", .bronze,
        metrics.days(atLeast: 100_000_000), 10),
      achievement(
        "two-tools", "双持法师", "2 个工具分别累计消耗至少 100M Token", "hammer", .bronze,
        metrics.providers(atLeast: 100_000_000), 2),
      achievement(
        "three-tools", "三路并行", "3 个工具分别累计消耗至少 100M Token", "hammer.fill", .bronze,
        metrics.providers(atLeast: 100_000_000), 3),
      achievement(
        "three-models", "模型初探", "3 个已知模型身份分别消耗至少 10M Token", "cube", .bronze,
        metrics.models(atLeast: 10_000_000), 3),
      achievement(
        "ten-models", "模型收藏家", "10 个已知模型身份分别消耗至少 10M Token", "cube.transparent", .bronze,
        metrics.models(atLeast: 10_000_000), 10),
      achievement(
        "three-variants", "档位探索者", "3 个模型推理档位分别消耗至少 10M Token", "slider.horizontal.3", .bronze,
        metrics.variants(atLeast: 10_000_000), 3),
      cacheAchievement(
        "cache-25", "缓存学徒", "缓存命中率达到 25%，有效样本不少于 100M Token", "bolt", .bronze, targetRate: 0.25,
        minimumSample: 100_000_000),
      cacheAchievement(
        "cache-40", "缓存好手", "缓存命中率达到 40%，有效样本不少于 500M Token", "bolt.fill", .bronze,
        targetRate: 0.40, minimumSample: 500_000_000),
      achievement(
        "billion-cache-read", "复用达人", "累计读取 1B 缓存 Token", "arrow.triangle.2.circlepath", .bronze,
        metrics.total.cacheRead, 1_000_000_000),
      achievement(
        "hundred-records", "百次留痕", "累计产生 100 条有效用量记录", "list.number", .bronze, metrics.recordCount,
        100),
      achievement(
        "thousand-records", "千次留痕", "累计产生 1,000 条有效用量记录", "list.number", .bronze,
        metrics.recordCount, 1_000),
      comingSoon("hundred-focus-hours", "百时研修", "累计估算专注 100 小时", "clock", .bronze),
      comingSoon(
        "thousand-dollar-spend", "千金初账", "累计等价 API 成本达到 US$1,000", "dollarsign.circle", .bronze),
    ]
  }

  private var silverAchievements: [Achievement] {
    [
      achievement(
        "billion-tokens", "十亿卷宗", "累计消耗 1B Token", "books.vertical", .silver, metrics.total.total,
        1_000_000_000),
      achievement(
        "five-billion-tokens", "五十亿藏书", "累计消耗 5B Token", "books.vertical.fill", .silver,
        metrics.total.total, 5_000_000_000),
      achievement(
        "daily-billion", "单日十亿", "任意自然日消耗 1B Token", "chart.bar.fill", .silver,
        metrics.maxDailyTokens, 1_000_000_000),
      achievement(
        "weekly-five-billion", "一周五十亿", "任意自然周消耗 5B Token", "calendar", .silver,
        metrics.maxWeeklyTokens, 5_000_000_000),
      achievement(
        "billion-output", "输出洪流", "累计产生 1B 输出 Token", "arrow.up.circle.fill", .silver,
        metrics.total.output, 1_000_000_000),
      achievement(
        "billion-reasoning", "深思星海", "累计产生 1B 推理 Token", "brain.head.profile.fill", .silver,
        metrics.total.reasoning, 1_000_000_000),
      achievement(
        "ten-billion-cache-read", "缓存百亿", "累计读取 10B 缓存 Token", "externaldrive.fill", .silver,
        metrics.total.cacheRead, 10_000_000_000),
      achievement(
        "fourteen-day-streak", "双周连击", "最长连续活跃 14 天", "flame.fill", .silver, metrics.longestStreak,
        14),
      achievement(
        "thirty-day-streak", "月度不辍", "最长连续活跃 30 天", "flame.fill", .silver, metrics.longestStreak, 30
      ),
      achievement(
        "hundred-eighty-active-days", "半年同行", "累计活跃 180 天", "calendar", .silver, metrics.activeDays,
        180),
      achievement(
        "four-tools", "四象集结", "4 个工具分别累计消耗至少 1B Token", "hammer.circle.fill", .silver,
        metrics.providers(atLeast: 1_000_000_000), 4),
      achievement(
        "twenty-five-models", "模型博览", "25 个已知模型身份分别消耗至少 100M Token", "cube.transparent.fill",
        .silver, metrics.models(atLeast: 100_000_000), 25),
      cacheAchievement(
        "cache-whisperer", "缓存专家", "缓存命中率达到 60%，有效样本不少于 10B Token", "leaf.fill", .silver,
        targetRate: 0.60, minimumSample: 10_000_000_000),
      comingSoon("thousand-focus-hours", "千时行者", "累计估算专注 1,000 小时", "clock.fill", .silver),
      comingSoon(
        "ten-thousand-dollar-spend", "万金账簿", "累计等价 API 成本达到 US$10,000", "dollarsign.circle.fill",
        .silver),
    ]
  }

  private var goldAchievements: [Achievement] {
    [
      achievement(
        "ten-billion-tokens", "百亿先生", "累计消耗 10B Token", "sparkles.rectangle.stack", .gold,
        metrics.total.total, 10_000_000_000),
      achievement(
        "hundred-billion-tokens", "千亿星河", "累计消耗 100B Token", "sparkles", .gold, metrics.total.total,
        100_000_000_000),
      achievement(
        "daily-ten-billion", "单日百亿", "任意自然日消耗 10B Token", "chart.bar.xaxis", .gold,
        metrics.maxDailyTokens, 10_000_000_000),
      achievement(
        "hundred-day-streak", "百日连击", "最长连续活跃 100 天", "flame.fill", .gold, metrics.longestStreak,
        100),
      achievement(
        "three-hundred-sixty-five-active-days", "全年留痕", "累计活跃 365 天", "calendar.badge.checkmark",
        .gold, metrics.activeDays, 365),
      achievement(
        "thousand-active-days", "千日同行", "累计活跃 1,000 天", "calendar", .gold, metrics.activeDays, 1_000
      ),
      achievement(
        "four-tools-master", "四象宗师", "4 个工具分别累计消耗至少 10B Token", "hammer.circle", .gold,
        metrics.providers(atLeast: 10_000_000_000), 4),
      cacheAchievement(
        "cache-75", "缓存大师", "缓存命中率达到 75%，有效样本不少于 100B Token", "bolt.shield.fill", .gold,
        targetRate: 0.75, minimumSample: 100_000_000_000),
      comingSoon("five-thousand-focus-hours", "五千时大法师", "累计估算专注 5,000 小时", "hourglass", .gold),
      comingSoon(
        "hundred-thousand-dollar-spend", "十万金库", "累计等价 API 成本达到 US$100,000", "banknote.fill", .gold),
    ]
  }

  private var diamondAchievements: [Achievement] {
    [
      achievement(
        "trillion-tokens", "万亿先生", "累计消耗 1T Token", "diamond.fill", .diamond, metrics.total.total,
        1_000_000_000_000),
      comingSoon(
        "million-dollar-spend", "挥金如土", "累计等价 API 成本达到 US$1,000,000", "dollarsign.square.fill",
        .diamond),
      hidden("diamond-reserved-1"),
      hidden("diamond-reserved-2"),
      hidden("diamond-reserved-3"),
    ]
  }

  private func achievement(
    _ id: String,
    _ title: String,
    _ detail: String,
    _ systemImage: String,
    _ tier: BadgeTier,
    _ value: Int,
    _ target: Int
  ) -> Achievement {
    Achievement(
      id: id,
      title: title,
      detail: detail,
      systemImage: systemImage,
      tier: tier,
      progress: min(1, Double(value) / Double(target)),
      progressLabel: "\(compact(value)) / \(compact(target))",
      availability: .active,
      criteriaVersion: 1
    )
  }

  private func cacheAchievement(
    _ id: String,
    _ title: String,
    _ detail: String,
    _ systemImage: String,
    _ tier: BadgeTier,
    targetRate: Double,
    minimumSample: Int
  ) -> Achievement {
    let sampleProgress = Double(metrics.cacheSample) / Double(minimumSample)
    let rateProgress = metrics.total.cacheHitRate / targetRate
    return Achievement(
      id: id,
      title: title,
      detail: detail,
      systemImage: systemImage,
      tier: tier,
      progress: min(1, sampleProgress, rateProgress),
      progressLabel:
        "\(metrics.total.cacheHitRate.formatted(.percent.precision(.fractionLength(0)))) · 样本 \(compact(metrics.cacheSample))",
      availability: .active,
      criteriaVersion: 1
    )
  }

  private func comingSoon(
    _ id: String,
    _ title: String,
    _ detail: String,
    _ systemImage: String,
    _ tier: BadgeTier
  ) -> Achievement {
    Achievement(
      id: id,
      title: title,
      detail: detail,
      systemImage: systemImage,
      tier: tier,
      progress: 0,
      progressLabel: "尚未开放",
      availability: .comingSoon,
      criteriaVersion: 1
    )
  }

  private func hidden(_ id: String) -> Achievement {
    Achievement(
      id: id,
      title: "预留席位",
      detail: "",
      systemImage: "diamond",
      tier: .diamond,
      progress: 0,
      progressLabel: "",
      availability: .hidden,
      criteriaVersion: 1
    )
  }

  private func compact(_ value: Int) -> String {
    value.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))
  }

  private static func makeMetrics(
    events: [UsageEvent],
    now: Date,
    calendar: Calendar
  ) -> AchievementMetrics {
    var total = TokenUsage.zero
    var dailyTotals: [Date: TokenUsage] = [:]
    var weeklyTotals: [Date: TokenUsage] = [:]
    var providerTotals: [AIProvider: TokenUsage] = [:]
    var modelTotals: [ModelIdentity: TokenUsage] = [:]

    for event in events {
      total = total + event.usage
      let day = calendar.startOfDay(for: event.timestamp)
      dailyTotals[day, default: .zero] = dailyTotals[day, default: .zero] + event.usage
      if let week = calendar.dateInterval(of: .weekOfYear, for: event.timestamp)?.start {
        weeklyTotals[week, default: .zero] = weeklyTotals[week, default: .zero] + event.usage
      }
      providerTotals[event.provider, default: .zero] =
        providerTotals[event.provider, default: .zero] + event.usage
      if event.model.isKnown {
        modelTotals[event.model, default: .zero] =
          modelTotals[event.model, default: .zero] + event.usage
      }
    }

    let days = Set(dailyTotals.keys)
    let weeks = Set(days.compactMap { calendar.dateInterval(of: .weekOfYear, for: $0)?.start })
    let months = Set(days.compactMap { calendar.dateInterval(of: .month, for: $0)?.start })
    let streaks = streaks(for: days, now: now, calendar: calendar)
    return AchievementMetrics(
      total: total,
      dailyTotals: dailyTotals,
      weeklyTotals: weeklyTotals,
      providerTotals: providerTotals,
      modelTotals: modelTotals,
      recordCount: events.count,
      activeDays: days.count,
      activeWeeks: weeks.count,
      activeMonths: months.count,
      currentStreak: streaks.current,
      longestStreak: streaks.longest
    )
  }

  private static func streaks(
    for days: Set<Date>,
    now: Date,
    calendar: Calendar
  ) -> (current: Int, longest: Int) {
    guard !days.isEmpty else { return (0, 0) }
    let ordered = days.sorted()
    var longest = 1
    var run = 1
    for (previous, next) in zip(ordered, ordered.dropFirst()) {
      if calendar.date(byAdding: .day, value: 1, to: previous) == next {
        run += 1
        longest = max(longest, run)
      } else {
        run = 1
      }
    }

    let today = calendar.startOfDay(for: now)
    var cursor = days.contains(today) ? today : calendar.date(byAdding: .day, value: -1, to: today)!
    var current = 0
    while days.contains(cursor) {
      current += 1
      cursor = calendar.date(byAdding: .day, value: -1, to: cursor)!
    }
    return (current, longest)
  }
}

private struct AchievementMetrics: Sendable {
  let total: TokenUsage
  let dailyTotals: [Date: TokenUsage]
  let weeklyTotals: [Date: TokenUsage]
  let providerTotals: [AIProvider: TokenUsage]
  let modelTotals: [ModelIdentity: TokenUsage]
  let recordCount: Int
  let activeDays: Int
  let activeWeeks: Int
  let activeMonths: Int
  let currentStreak: Int
  let longestStreak: Int

  var maxDailyTokens: Int { dailyTotals.values.map(\.total).max() ?? 0 }
  var maxWeeklyTokens: Int { weeklyTotals.values.map(\.total).max() ?? 0 }
  var cacheSample: Int { total.input + total.cacheRead + total.cacheWrite }

  func days(atLeast target: Int) -> Int {
    dailyTotals.values.count { $0.total >= target }
  }

  func providers(atLeast target: Int) -> Int {
    providerTotals.values.count { $0.total >= target }
  }

  func models(atLeast target: Int) -> Int {
    modelTotals.values.count { $0.total >= target }
  }

  func variants(atLeast target: Int) -> Int {
    modelTotals.count { model, usage in model.variant != nil && usage.total >= target }
  }
}
