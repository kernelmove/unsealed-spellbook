import Charts
import SwiftUI
import UnsealedSpellbookCore

struct DetailDashboardView: View {
  let analytics: UsageAnalytics

  @State private var period: UsagePeriod = .last7Days
  @State private var selectedProvider: AIProvider = .codex

  var body: some View {
    ScrollView {
      VStack(spacing: SpellbookDesign.spacing) {
        HStack(alignment: .top, spacing: SpellbookDesign.spacing) {
          TotalUsagePanel(analytics: analytics, period: $period)
            .frame(maxWidth: .infinity)

          ToolDetailPanel(
            analytics: analytics,
            provider: $selectedProvider,
            period: period
          )
          .frame(width: SpellbookDesign.sidebarWidth)
          .frame(maxHeight: .infinity)
        }

        ToolTrendPanel(analytics: analytics, provider: selectedProvider, period: period)
        ModelRankingPanel(analytics: analytics)
      }
      .padding(SpellbookDesign.spacing)
    }
    .background(SpellbookDesign.surfaceSoft)
  }
}

private struct TotalUsagePanel: View {
  let analytics: UsageAnalytics
  @Binding var period: UsagePeriod

  var body: some View {
    let snapshot = analytics.snapshot(for: period)
    let dailyUsage = analytics.dailyUsage(for: period)

    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top, spacing: 16) {
        VStack(alignment: .leading, spacing: 7) {
          Text("总 Token")
            .font(.system(size: 15, weight: .semibold))
          Text(snapshot.total.total.compactTokenCount)
            .font(.system(size: 48, weight: .semibold))
            .tracking(-1.9)
            .monospacedDigit()
            .contentTransition(.numericText())
          Text("所选周期内全部工具")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Spacer(minLength: 0)

        PeriodTabs(selection: $period)
      }

      Text("工具使用占比")
        .font(.system(size: 15, weight: .semibold))
        .padding(.top, 28)
        .padding(.bottom, 12)

      VStack(spacing: 13) {
        ForEach(AIProvider.allCases, id: \.rawValue) { provider in
          ProviderContributionRow(
            provider: provider,
            usage: snapshot.providers[provider] ?? .zero,
            total: snapshot.total.total
          )
        }
      }

      Divider()
        .overlay(SpellbookDesign.line)
        .padding(.top, 20)
        .padding(.bottom, 18)

      HStack(alignment: .firstTextBaseline) {
        Text("按日趋势")
          .font(.system(size: 15, weight: .semibold))
        Spacer()
        Text(periodCaption)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .padding(.bottom, 6)

      DailyUsageHeatmap(
        data: dailyUsage,
        now: analytics.now,
        calendar: analytics.calendar,
        color: SpellbookDesign.metricBlue
      )
      .frame(height: 110)
    }
    .padding(.vertical, 24)
    .padding(.horizontal, 28)
    .spellbookPanel()
  }

  private var periodCaption: String {
    if period == .today {
      return "截至 \(analytics.now.formatted(.dateTime.hour().minute()))"
    }
    return period.displayName
  }
}

private struct ToolDetailPanel: View {
  let analytics: UsageAnalytics
  @Binding var provider: AIProvider
  let period: UsagePeriod

  private let columns = [
    GridItem(.flexible(), spacing: 10),
    GridItem(.flexible(), spacing: 10),
  ]

  var body: some View {
    let snapshot = analytics.snapshot(for: period, provider: provider)

    VStack(alignment: .leading, spacing: 14) {
      Text("工具详情")
        .font(.system(size: 18, weight: .semibold))

      SpellbookSegmentedControl(
        options: AIProvider.allCases,
        selection: $provider,
        horizontalPadding: 3
      ) { $0 == .claudeCode ? "Claude" : $0.displayName }
      .font(.system(size: 11))
      .accessibilityLabel("选择统计工具")

      LazyVGrid(columns: columns, spacing: 10) {
        MetricTile(title: "总计", value: snapshot.total.total, color: provider.tintColor)
        MetricTile(title: "输入", value: snapshot.total.input, color: SpellbookDesign.metricBlue)
        MetricTile(
          title: "输出",
          value: snapshot.total.output,
          color: SpellbookDesign.metricPurple
        )
        MetricTile(
          title: "缓存",
          value: snapshot.total.cacheRead + snapshot.total.cacheWrite,
          color: SpellbookDesign.success
        )
      }

      Text("所有数值均继承全局时间范围。零值工具仍可选择。")
        .font(.caption)
        .foregroundStyle(.secondary)

      Spacer(minLength: 0)
    }
    .padding(20)
    .frame(maxHeight: .infinity, alignment: .topLeading)
    .spellbookPanel()
  }
}

private struct ToolTrendPanel: View {
  let analytics: UsageAnalytics
  let provider: AIProvider
  let period: UsagePeriod

  var body: some View {
    let dailyUsage = analytics.dailyUsage(for: period, provider: provider)

    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("\(provider.displayName) · 按日趋势")
          .font(.system(size: 15, weight: .semibold))
        Spacer()
        Text(period.displayName)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      DailyUsageChart(data: dailyUsage, color: provider.tintColor)
        .frame(height: 170)
    }
    .padding(20)
    .spellbookPanel()
  }
}

private struct ModelRankingPanel: View {
  let analytics: UsageAnalytics

  var body: some View {
    let rankings = analytics.modelRankings(for: .today)

    VStack(alignment: .leading, spacing: 12) {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text("今日模型排名")
            .font(.headline)
          Text("模型与推理档位分别统计 · 按 Token 排序")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Text("\(rankings.count) 个模型")
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
      }

      if rankings.isEmpty {
        Label("今天还没有模型调用", systemImage: "chart.bar.xaxis")
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, minHeight: 80)
      } else {
        ForEach(Array(rankings.enumerated()), id: \.element.id) { index, summary in
          ModelRankingRow(rank: index + 1, summary: summary)
          if index < rankings.count - 1 {
            Divider().overlay(SpellbookDesign.line)
          }
        }
      }
    }
    .padding(20)
    .spellbookPanel()
  }
}

struct PeriodTabs: View {
  static let options = UsagePeriod.allCases

  @Binding var selection: UsagePeriod

  var body: some View {
    SpellbookSegmentedControl(
      options: Self.options,
      selection: $selection,
      horizontalPadding: 6
    ) { $0.displayName }
    .font(.system(size: 12, weight: .medium))
    .frame(width: 360)
    .accessibilityLabel("统计时间范围")
  }
}

private struct ProviderContributionRow: View {
  let provider: AIProvider
  let usage: TokenUsage
  let total: Int

  private var share: Double {
    total == 0 ? 0 : Double(usage.total) / Double(total)
  }

  var body: some View {
    HStack(spacing: 12) {
      HStack(spacing: 9) {
        Image(systemName: provider.systemImage)
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(provider.tintColor)
          .frame(width: 24, height: 24)
          .background(SpellbookDesign.iconBackground, in: RoundedRectangle(cornerRadius: 6))
        Text(provider.displayName)
          .font(.subheadline)
          .lineLimit(1)
      }
      .frame(width: 134, alignment: .leading)

      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          Capsule().fill(SpellbookDesign.track)
          Capsule()
            .fill(provider.tintColor)
            .frame(width: max(3, proxy.size.width * share))
        }
      }
      .frame(height: 7)

      Text(usage.total.compactTokenCount)
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
        .frame(width: 78, alignment: .trailing)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(provider.displayName)，\(usage.total.formatted()) Token")
  }
}

private struct MetricTile: View {
  let title: String
  let value: Int
  let color: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
      Spacer(minLength: 12)
      Text(value.compactTokenCount)
        .font(.system(size: 23, weight: .semibold))
        .tracking(-0.45)
        .monospacedDigit()
        .foregroundStyle(color)
      Text("Token")
        .font(.caption)
        .foregroundStyle(.tertiary)
        .padding(.top, 4)
    }
    .padding(14)
    .frame(maxWidth: .infinity, minHeight: 116, alignment: .leading)
    .background(
      SpellbookDesign.surface,
      in: RoundedRectangle(cornerRadius: 12, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .stroke(SpellbookDesign.line, lineWidth: 1)
    }
    .accessibilityElement(children: .combine)
  }
}

struct DailyUsageHeatmapCell: Identifiable {
  let day: Date
  let tokens: Int?
  let level: Int
  let isFuture: Bool

  var id: Date { day }
}

enum DailyUsageHeatmapLayout {
  static let columnCount = 52
  static let rowCount = 7

  static func cells(
    for data: [DailyUsage],
    now: Date,
    calendar: Calendar
  ) -> [DailyUsageHeatmapCell] {
    guard
      let firstDay = data.first?.day,
      let lastDay = data.last?.day,
      let lastWeek = calendar.dateInterval(of: .weekOfYear, for: lastDay),
      let gridStart = calendar.date(
        byAdding: .weekOfYear,
        value: -(columnCount - 1),
        to: lastWeek.start
      )
    else { return [] }

    let selectedStart = calendar.startOfDay(for: firstDay)
    let selectedEnd = calendar.startOfDay(for: lastDay)
    let today = calendar.startOfDay(for: now)
    let totals = Dictionary(
      uniqueKeysWithValues: data.map {
        (calendar.startOfDay(for: $0.day), $0.usage.total)
      }
    )
    let maximum = max(1, totals.values.max() ?? 0)

    return (0..<(columnCount * rowCount)).compactMap { offset in
      guard let day = calendar.date(byAdding: .day, value: offset, to: gridStart) else {
        return nil
      }
      let isSelected = day >= selectedStart && day <= selectedEnd
      let tokens = isSelected ? totals[day] ?? 0 : nil
      let isFuture = day > today
      return DailyUsageHeatmapCell(
        day: day,
        tokens: tokens,
        level: isFuture ? 0 : intensityLevel(tokens: tokens ?? 0, maximum: maximum),
        isFuture: isFuture
      )
    }
  }

  static func intensityLevel(tokens: Int, maximum: Int) -> Int {
    guard tokens > 0, maximum > 0 else { return 0 }
    let scaled = log1p(Double(tokens)) / log1p(Double(maximum))
    return min(4, max(1, Int(ceil(scaled * 4))))
  }
}

private struct DailyUsageHeatmap: View {
  let data: [DailyUsage]
  let now: Date
  let calendar: Calendar
  let color: Color

  private let cellSize: CGFloat = 9
  private let spacing: CGFloat = 2.5
  private let rows = Array(
    repeating: GridItem(.fixed(9), spacing: 2.5),
    count: DailyUsageHeatmapLayout.rowCount
  )

  private var cells: [DailyUsageHeatmapCell] {
    DailyUsageHeatmapLayout.cells(for: data, now: now, calendar: calendar)
  }

  private var monthMarkers: [(column: Int, day: Date)] {
    var previousMonth: Int?
    return cells.enumerated().compactMap { index, cell in
      let month = calendar.component(.month, from: cell.day)
      guard month != previousMonth else { return nil }
      previousMonth = month
      if index == 0, calendar.component(.day, from: cell.day) > 7 { return nil }
      return (index / DailyUsageHeatmapLayout.rowCount, cell.day)
    }
  }

  private var gridWidth: CGFloat {
    CGFloat(DailyUsageHeatmapLayout.columnCount) * cellSize
      + CGFloat(DailyUsageHeatmapLayout.columnCount - 1) * spacing
  }

  private var gridHeight: CGFloat {
    CGFloat(DailyUsageHeatmapLayout.rowCount) * cellSize
      + CGFloat(DailyUsageHeatmapLayout.rowCount - 1) * spacing
  }

  private var accessibilitySummary: String {
    data.map {
      "\($0.day.formatted(.dateTime.month().day()))，\($0.usage.total.formatted()) Token"
    }.joined(separator: "；")
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      LazyHGrid(rows: rows, spacing: spacing) {
        ForEach(cells) { cell in
          let helpText = helpText(for: cell)
          RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(fill(for: cell))
            .frame(width: cellSize, height: cellSize)
            .help(helpText)
            .accessibilityHidden(cell.tokens == nil || cell.isFuture)
            .accessibilityLabel(helpText)
        }
      }
      .frame(width: gridWidth, height: gridHeight)

      ZStack(alignment: .leading) {
        ForEach(Array(monthMarkers.enumerated()), id: \.offset) { _, marker in
          Text(marker.day.formatted(.dateTime.month(.abbreviated)))
            .font(.caption2)
            .foregroundStyle(.secondary)
            .offset(x: CGFloat(marker.column) * (cellSize + spacing))
        }
      }
      .frame(width: gridWidth, height: 14, alignment: .leading)
    }
    .frame(maxWidth: .infinity, alignment: .center)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("按日 Token 活跃度方阵")
    .accessibilityValue(accessibilitySummary)
  }

  private func fill(for cell: DailyUsageHeatmapCell) -> Color {
    if cell.tokens == nil { return SpellbookDesign.track.opacity(0.55) }
    if cell.isFuture { return SpellbookDesign.track.opacity(0.70) }
    guard cell.level > 0 else { return SpellbookDesign.track }
    return color.opacity([0, 0.25, 0.45, 0.70, 1][cell.level])
  }

  private func helpText(for cell: DailyUsageHeatmapCell) -> String {
    let date = cell.day.formatted(.dateTime.year().month().day())
    guard let tokens = cell.tokens else { return "\(date)，不在所选周期" }
    if cell.isFuture { return "\(date)，尚未发生" }
    return "\(date)，\(tokens.formatted()) Token"
  }
}

private struct DailyUsageChart: View {
  let data: [DailyUsage]
  let color: Color

  private var maximum: Int {
    max(1, data.map { $0.usage.total }.max() ?? 0)
  }

  private var total: Int {
    data.reduce(0) { $0 + $1.usage.total }
  }

  private var accessibilitySummary: String {
    data.map {
      "\($0.day.formatted(.dateTime.month().day()))，\($0.usage.total.formatted()) Token"
    }.joined(separator: "；")
  }

  var body: some View {
    ZStack {
      Chart(data) { item in
        AreaMark(
          x: .value("日期", item.day, unit: .day),
          y: .value("Token", item.usage.total)
        )
        .interpolationMethod(.monotone)
        .foregroundStyle(
          LinearGradient(
            colors: [color.opacity(0.22), color.opacity(0)],
            startPoint: .top,
            endPoint: .bottom
          )
        )

        LineMark(
          x: .value("日期", item.day, unit: .day),
          y: .value("Token", item.usage.total)
        )
        .interpolationMethod(.monotone)
        .foregroundStyle(color)
        .lineStyle(StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))

        if item.id == data.last?.id {
          PointMark(
            x: .value("日期", item.day, unit: .day),
            y: .value("Token", item.usage.total)
          )
          .foregroundStyle(SpellbookDesign.surface)
          .symbolSize(54)
          .annotation(position: .overlay) {
            Circle()
              .stroke(color, lineWidth: 3)
              .frame(width: 10, height: 10)
          }
        }
      }
      .chartYScale(domain: 0...maximum)
      .chartXAxis {
        AxisMarks(values: .automatic(desiredCount: min(data.count, 7))) {
          AxisValueLabel(format: .dateTime.month().day())
        }
      }
      .chartYAxis {
        AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
          AxisGridLine().foregroundStyle(SpellbookDesign.line)
          AxisValueLabel {
            if let tokens = value.as(Int.self) {
              Text(tokens.compactTokenCount)
            }
          }
        }
      }

      if total == 0 {
        Text("暂无记录")
          .font(.caption)
          .foregroundStyle(.tertiary)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("按日 Token 消耗图")
    .accessibilityValue(accessibilitySummary)
  }

}

private struct ModelRankingRow: View {
  let rank: Int
  let summary: ModelUsageSummary

  private var source: String {
    [summary.model.tool?.displayName, summary.model.backend]
      .compactMap { $0 }
      .joined(separator: " · ")
  }

  var body: some View {
    HStack(alignment: .top, spacing: 11) {
      Text("\(rank)")
        .font(.caption.bold().monospacedDigit())
        .foregroundStyle(.secondary)
        .frame(width: 22, height: 22)
        .background(SpellbookDesign.iconBackground, in: Circle())

      VStack(alignment: .leading, spacing: 6) {
        HStack(alignment: .firstTextBaseline) {
          VStack(alignment: .leading, spacing: 2) {
            Text(summary.model.displayName)
              .font(.subheadline.weight(.semibold))
              .lineLimit(1)
            if !source.isEmpty {
              Text(source)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
          }
          Spacer()
          VStack(alignment: .trailing, spacing: 2) {
            Text(summary.usage.total.compactTokenCount)
              .font(.subheadline.weight(.semibold).monospacedDigit())
            Text("\(summary.recordCount) 条用量记录")
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
        }

        HStack(spacing: 8) {
          Text("缓存命中")
            .font(.caption)
            .foregroundStyle(.secondary)
          ProgressView(value: summary.cacheHitRate)
            .tint(SpellbookDesign.success)
          Text(summary.cacheHitRate.formatted(.percent.precision(.fractionLength(0))))
            .font(.caption.monospacedDigit())
            .frame(width: 38, alignment: .trailing)
        }
      }
    }
    .accessibilityElement(children: .combine)
  }
}
