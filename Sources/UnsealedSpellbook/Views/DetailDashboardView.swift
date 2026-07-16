import Charts
import SwiftUI
import UnsealedSpellbookCore
import UnsealedSpellbookLanguage

struct DetailDashboardView: View {
  let analytics: UsageAnalytics
  let pricingCatalog: PricingCatalog?

  @State private var period: UsagePeriod = .last7Days
  @State private var selectedProvider: AIProvider = .codex
  @State private var perspective: UsagePerspective

  init(
    analytics: UsageAnalytics,
    pricingCatalog: PricingCatalog?,
    initialPerspective: UsagePerspective = .tokens
  ) {
    self.analytics = analytics
    self.pricingCatalog = pricingCatalog
    _perspective = State(initialValue: initialPerspective)
  }

  var body: some View {
    ScrollView {
      VStack(spacing: SpellbookDesign.spacing) {
        HStack(spacing: 8) {
          Spacer()
          SpellbookSegmentedControl(
            options: pricingCatalog == nil ? [.tokens] : UsagePerspective.allCases,
            selection: $perspective,
            horizontalPadding: 10
          ) { $0.title(language: language) }
          .font(.system(size: 12, weight: .medium))
          .frame(width: 150)

          if perspective == .cost {
            Link(destination: PricingDocumentation.url) {
              Image(systemName: "info.circle")
            }
            .help(language.text(.actionOpenPricingRules))
            .accessibilityLabel(language.text(.actionOpenPricingRules))
          }
        }

        HStack(alignment: .top, spacing: SpellbookDesign.spacing) {
          TotalUsagePanel(
            analytics: analytics,
            catalog: pricingCatalog,
            perspective: perspective,
            period: $period
          )
          .frame(maxWidth: .infinity)

          ToolDetailPanel(
            analytics: analytics,
            catalog: pricingCatalog,
            perspective: perspective,
            provider: $selectedProvider,
            period: period
          )
          .frame(width: SpellbookDesign.sidebarWidth)
          .frame(maxHeight: .infinity)
        }

        ToolTrendPanel(
          analytics: analytics,
          catalog: pricingCatalog,
          perspective: perspective,
          provider: selectedProvider,
          period: period
        )
        ModelRankingPanel(
          analytics: analytics,
          catalog: pricingCatalog,
          perspective: perspective
        )
      }
      .padding(SpellbookDesign.spacing)
    }
    .background(SpellbookDesign.surfaceSoft)
  }

  @Environment(\.appLanguage) private var language
}

enum UsagePerspective: CaseIterable, Hashable {
  case tokens
  case cost

  func title(language: AppLanguage) -> String {
    language.text(self == .tokens ? .perspectiveTokens : .perspectiveCost)
  }
}

private enum PricingDocumentation {
  static let url = URL(
    string: "https://github.com/kernelmove/unsealed-spellbook/blob/main/docs/pricing.md"
  )!
}

private struct TotalUsagePanel: View {
  let analytics: UsageAnalytics
  let catalog: PricingCatalog?
  let perspective: UsagePerspective
  @Binding var period: UsagePeriod
  @Environment(\.appLanguage) private var language

  var body: some View {
    let snapshot = perspective == .tokens ? analytics.snapshot(for: period) : nil
    let dailyUsage = perspective == .tokens ? analytics.dailyUsage(for: period) : []
    let costSnapshot =
      perspective == .cost
      ? catalog.map { analytics.costSnapshot(for: period, catalog: $0) }
      : nil
    let dailyCost =
      perspective == .cost
      ? catalog.map { analytics.dailyCost(for: period, catalog: $0) } ?? []
      : []

    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top, spacing: 16) {
        VStack(alignment: .leading, spacing: 7) {
          Text(
            language.text(
              perspective == .tokens ? .overviewTotalTokens : .overviewTotalCost
            )
          )
          .font(.system(size: 15, weight: .semibold))
          Text(totalValue(snapshot: snapshot, costSnapshot: costSnapshot))
            .font(.system(size: 48, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .tracking(-1.9)
            .monospacedDigit()
            .contentTransition(.numericText())
          Text(language.text(.overviewAllTools))
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Spacer(minLength: 0)

        PeriodTabs(selection: $period)
      }

      Text(
        language.text(
          perspective == .tokens ? .overviewToolUsageShare : .overviewToolCostShare
        )
      )
      .font(.system(size: 15, weight: .semibold))
      .padding(.top, 28)
      .padding(.bottom, 12)

      VStack(spacing: 13) {
        ForEach(AIProvider.allCases, id: \.rawValue) { provider in
          if perspective == .tokens {
            ProviderContributionRow(
              provider: provider,
              value: Double(snapshot?.providers[provider]?.total ?? 0),
              total: Double(snapshot?.total.total ?? 0),
              valueText: (snapshot?.providers[provider]?.total ?? 0).compactTokenCount(
                language: language
              )
            )
          } else {
            ProviderContributionRow(
              provider: provider,
              value: costSnapshot?.providers[provider]?.total ?? 0,
              total: costSnapshot?.total.total ?? 0,
              valueText: (costSnapshot?.providers[provider]?.total ?? 0).compactUSDCost()
            )
          }
        }
      }

      if perspective == .cost, let costSnapshot, costSnapshot.unpricedTokens > 0 {
        Label(
          language.text(
            .overviewUnpricedFormat,
            costSnapshot.unpricedTokens,
            costSnapshot.unpricedModels.count
          ),
          systemImage: "exclamationmark.circle"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.top, 12)
      }

      Divider()
        .overlay(SpellbookDesign.line)
        .padding(.top, 20)
        .padding(.bottom, 18)

      HStack(alignment: .firstTextBaseline) {
        Text(language.text(.overviewDailyTrend))
          .font(.system(size: 15, weight: .semibold))
        Spacer()
        Text(periodCaption)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .padding(.bottom, 6)

      DailyMetricHeatmap(
        data: perspective == .tokens
          ? dailyUsage.map { DailyMetric(day: $0.day, value: Double($0.usage.total)) }
          : dailyCost.map { DailyMetric(day: $0.day, value: $0.cost.total) },
        now: analytics.now,
        calendar: analytics.calendar,
        color: SpellbookDesign.metricBlue,
        accessibilityTitle: language.text(
          perspective == .tokens ? .accessibilityDailyHeatmap : .accessibilityDailyCostChart
        ),
        valueText: { value in
          if perspective == .tokens {
            return Int(value).formatted(.number.locale(language.locale)) + " Token"
          }
          return value.compactUSDCost()
        }
      )
      .frame(height: 110)
    }
    .padding(.vertical, 24)
    .padding(.horizontal, 28)
    .spellbookPanel()
  }

  private func totalValue(snapshot: UsageSnapshot?, costSnapshot: CostSnapshot?) -> String {
    if perspective == .tokens {
      return (snapshot?.total.total ?? 0).compactTokenCount(language: language)
    }
    return (costSnapshot?.total.total ?? 0).compactUSDCost()
  }

  private var periodCaption: String {
    if period == .today {
      return language.text(
        .overviewAsOfFormat,
        analytics.now.formatted(.dateTime.hour().minute().locale(language.locale))
      )
    }
    return period.displayName(language: language)
  }
}

private struct ToolDetailPanel: View {
  let analytics: UsageAnalytics
  let catalog: PricingCatalog?
  let perspective: UsagePerspective
  @Binding var provider: AIProvider
  let period: UsagePeriod
  @Environment(\.appLanguage) private var language

  private let columns = [
    GridItem(.flexible(), spacing: 10),
    GridItem(.flexible(), spacing: 10),
  ]

  var body: some View {
    let snapshot =
      perspective == .tokens
      ? analytics.snapshot(for: period, provider: provider)
      : nil
    let cost =
      perspective == .cost
      ? catalog.map {
        analytics.costSnapshot(for: period, provider: provider, catalog: $0).total
      }
      : nil

    VStack(alignment: .leading, spacing: 14) {
      Text(language.text(.toolDetails))
        .font(.system(size: 18, weight: .semibold))

      ScrollView(.horizontal, showsIndicators: false) {
        SpellbookSegmentedControl(
          options: AIProvider.allCases,
          selection: $provider,
          horizontalPadding: 7
        ) { shortName($0) }
        .fixedSize(horizontal: true, vertical: false)
      }
      .font(.system(size: 11))
      .accessibilityLabel(language.text(.accessibilitySelectTool))

      LazyVGrid(columns: columns, spacing: 10) {
        MetricTile(
          title: language.text(.metricTotal),
          value: metricValue(tokens: snapshot?.total.total ?? 0, cost: cost?.total),
          unit: metricUnit,
          color: provider.tintColor)
        MetricTile(
          title: language.text(.metricInput),
          value: metricValue(tokens: snapshot?.total.input ?? 0, cost: cost?.input),
          unit: metricUnit,
          color: SpellbookDesign.metricBlue)
        MetricTile(
          title: language.text(.metricOutput),
          value: metricValue(
            tokens: (snapshot?.total.output ?? 0) + (snapshot?.total.reasoning ?? 0),
            cost: cost?.output
          ),
          unit: metricUnit,
          color: SpellbookDesign.metricPurple
        )
        MetricTile(
          title: language.text(.metricCache),
          value: metricValue(
            tokens: (snapshot?.total.cacheRead ?? 0) + (snapshot?.total.cacheWrite ?? 0),
            cost: (cost?.cacheRead ?? 0) + (cost?.cacheWrite ?? 0)
          ),
          unit: metricUnit,
          color: SpellbookDesign.success
        )
      }

      Text(language.text(.toolPeriodNote))
        .font(.caption)
        .foregroundStyle(.secondary)

      Spacer(minLength: 0)
    }
    .padding(20)
    .frame(maxHeight: .infinity, alignment: .topLeading)
    .spellbookPanel()
  }

  private var metricUnit: String { perspective == .tokens ? "Token" : "USD" }

  private func metricValue(tokens: Int, cost: Double?) -> String {
    perspective == .tokens
      ? tokens.compactTokenCount(language: language)
      : (cost ?? 0).compactUSDCost()
  }

  private func shortName(_ provider: AIProvider) -> String {
    switch provider {
    case .claudeCode: "Claude"
    case .ohMyPi: "OMP"
    case .geminiCLI: "Gemini"
    default: provider.displayName
    }
  }
}

private struct ToolTrendPanel: View {
  let analytics: UsageAnalytics
  let catalog: PricingCatalog?
  let perspective: UsagePerspective
  let provider: AIProvider
  let period: UsagePeriod
  @Environment(\.appLanguage) private var language

  var body: some View {
    let dailyUsage =
      perspective == .tokens
      ? analytics.dailyUsage(for: period, provider: provider)
      : []
    let dailyCost =
      perspective == .cost
      ? catalog.map {
        analytics.dailyCost(for: period, provider: provider, catalog: $0)
      } ?? []
      : []

    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text(language.text(.toolDailyTrendFormat, provider.displayName))
          .font(.system(size: 15, weight: .semibold))
        Spacer()
        Text(period.displayName(language: language))
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      DailyMetricChart(
        data: perspective == .tokens
          ? dailyUsage.map { DailyMetric(day: $0.day, value: Double($0.usage.total)) }
          : dailyCost.map { DailyMetric(day: $0.day, value: $0.cost.total) },
        color: provider.tintColor,
        yAxisTitle: language.text(perspective == .tokens ? .chartToken : .chartCost),
        accessibilityTitle: language.text(
          perspective == .tokens
            ? .accessibilityDailyTokenChart : .accessibilityDailyCostChart
        ),
        valueText: { value in
          perspective == .tokens
            ? Int(value).compactTokenCount(language: language)
            : value.compactUSDCost()
        }
      )
      .frame(height: 170)
    }
    .padding(20)
    .spellbookPanel()
  }
}

private struct ModelRankingPanel: View {
  let analytics: UsageAnalytics
  let catalog: PricingCatalog?
  let perspective: UsagePerspective
  @Environment(\.appLanguage) private var language

  var body: some View {
    let rankings = perspective == .tokens ? analytics.modelRankings(for: .today) : []
    let costRankings =
      perspective == .cost
      ? catalog.map {
        analytics.modelCostRankings(for: .today, catalog: $0)
      } ?? []
      : []
    let count = perspective == .tokens ? rankings.count : costRankings.count

    VStack(alignment: .leading, spacing: 12) {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text(language.text(.rankingToday))
            .font(.headline)
          Text(
            language.text(
              perspective == .tokens ? .rankingDescription : .rankingCostDescription
            )
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
        Spacer()
        Text(language.text(.rankingModelCountFormat, count))
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
      }

      if count == 0 {
        Label(language.text(.rankingEmpty), systemImage: "chart.bar.xaxis")
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, minHeight: 80)
      } else {
        if perspective == .tokens {
          ForEach(Array(rankings.enumerated()), id: \.element.id) { index, summary in
            ModelRankingRow(
              rank: index + 1,
              model: summary.model,
              usage: summary.usage,
              recordCount: summary.recordCount,
              valueText: summary.usage.total.compactTokenCount(language: language)
            )
            if index < rankings.count - 1 {
              Divider().overlay(SpellbookDesign.line)
            }
          }
        } else {
          ForEach(Array(costRankings.enumerated()), id: \.element.id) { index, summary in
            ModelRankingRow(
              rank: index + 1,
              model: summary.model,
              usage: summary.usage,
              recordCount: summary.recordCount,
              valueText: summary.cost?.total.compactUSDCost() ?? "—"
            )
            if index < costRankings.count - 1 {
              Divider().overlay(SpellbookDesign.line)
            }
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
  @Environment(\.appLanguage) private var language

  var body: some View {
    SpellbookSegmentedControl(
      options: Self.options,
      selection: $selection,
      horizontalPadding: 6
    ) { $0.displayName(language: language) }
    .font(.system(size: 12, weight: .medium))
    .frame(width: 360)
    .accessibilityLabel(language.text(.accessibilityTimeRange))
  }
}

private struct ProviderContributionRow: View {
  let provider: AIProvider
  let value: Double
  let total: Double
  let valueText: String

  private var share: Double {
    total == 0 ? 0 : value / total
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

      Text(valueText)
        .font(.caption.monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .foregroundStyle(.secondary)
        .frame(width: 78, alignment: .trailing)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(provider.displayName), \(valueText)")
  }
}

private struct MetricTile: View {
  let title: String
  let value: String
  let unit: String
  let color: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
      Spacer(minLength: 12)
      Text(value)
        .font(.system(size: 23, weight: .semibold))
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .tracking(-0.45)
        .monospacedDigit()
        .foregroundStyle(color)
      Text(unit)
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

struct DailyMetric: Identifiable {
  let day: Date
  let value: Double
  var id: Date { day }
}

struct DailyMetricHeatmapCell: Identifiable {
  let day: Date
  let value: Double?
  let level: Int
  let isFuture: Bool
  var id: Date { day }
  var showsHoverDetail: Bool { value != nil && !isFuture }
}

enum DailyMetricHeatmapLayout {
  static let columnCount = 52
  static let rowCount = 7

  static func cells(
    for data: [DailyMetric],
    now: Date,
    calendar: Calendar
  ) -> [DailyMetricHeatmapCell] {
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
      uniqueKeysWithValues: data.map { (calendar.startOfDay(for: $0.day), $0.value) }
    )
    let maximum = max(Double.leastNonzeroMagnitude, totals.values.max() ?? 0)

    return (0..<(columnCount * rowCount))
      .compactMap { offset in
        guard let day = calendar.date(byAdding: .day, value: offset, to: gridStart) else {
          return nil
        }
        let value = day >= selectedStart && day <= selectedEnd ? totals[day] ?? 0 : nil
        let isFuture = day > today
        return DailyMetricHeatmapCell(
          day: day,
          value: value,
          level: isFuture ? 0 : intensityLevel(value: value ?? 0, maximum: maximum),
          isFuture: isFuture
        )
      }
  }

  static func intensityLevel(value: Double, maximum: Double) -> Int {
    guard value > 0, maximum > 0 else { return 0 }
    let scaled = log1p(value) / log1p(maximum)
    return min(4, max(1, Int(ceil(scaled * 4))))
  }
}

private struct DailyMetricHeatmap: View {
  let data: [DailyMetric]
  let now: Date
  let calendar: Calendar
  let color: Color
  let accessibilityTitle: String
  let valueText: (Double) -> String
  @Environment(\.appLanguage) private var language
  @State private var hoveredDay: Date?

  private let cellSize: CGFloat = 9
  private let spacing: CGFloat = 2.5
  private let hoverCardWidth: CGFloat = 144
  private let hoverCardHeight: CGFloat = 42
  private let rows = Array(
    repeating: GridItem(.fixed(9), spacing: 2.5),
    count: DailyMetricHeatmapLayout.rowCount
  )

  private func monthMarkers(
    in cells: [DailyMetricHeatmapCell]
  ) -> [(column: Int, day: Date)] {
    var previousMonth: Int?
    return cells.enumerated().compactMap { index, cell in
      let month = calendar.component(.month, from: cell.day)
      guard month != previousMonth else { return nil }
      previousMonth = month
      if index == 0, calendar.component(.day, from: cell.day) > 7 { return nil }
      return (index / DailyMetricHeatmapLayout.rowCount, cell.day)
    }
  }

  private var gridWidth: CGFloat {
    CGFloat(DailyMetricHeatmapLayout.columnCount) * cellSize
      + CGFloat(DailyMetricHeatmapLayout.columnCount - 1) * spacing
  }

  private var gridHeight: CGFloat {
    CGFloat(DailyMetricHeatmapLayout.rowCount) * cellSize
      + CGFloat(DailyMetricHeatmapLayout.rowCount - 1) * spacing
  }

  private var accessibilitySummary: String {
    data.map {
      "\($0.day.formatted(.dateTime.month().day().locale(language.locale))), \(valueText($0.value))"
    }.joined(separator: "; ")
  }

  var body: some View {
    let cells = DailyMetricHeatmapLayout.cells(for: data, now: now, calendar: calendar)
    let hoveredCell = cells.first { $0.day == hoveredDay && $0.showsHoverDetail }
    let monthMarkers = monthMarkers(in: cells)

    VStack(alignment: .leading, spacing: 8) {
      ZStack(alignment: .topLeading) {
        LazyHGrid(rows: rows, spacing: spacing) {
          ForEach(cells) { cell in
            let helpText = helpText(for: cell)
            RoundedRectangle(cornerRadius: 3, style: .continuous)
              .fill(fill(for: cell))
              .frame(width: cellSize, height: cellSize)
              .contentShape(Rectangle())
              .onHover { isHovering in
                guard cell.showsHoverDetail else { return }
                if isHovering {
                  hoveredDay = cell.day
                } else if hoveredDay == cell.day {
                  hoveredDay = nil
                }
              }
              .accessibilityHidden(!cell.showsHoverDetail)
              .accessibilityLabel(helpText)
          }
        }

        if let hoveredCell,
          let value = hoveredCell.value,
          let index = cells.firstIndex(where: { $0.id == hoveredCell.id })
        {
          let column = index / DailyMetricHeatmapLayout.rowCount
          let row = index % DailyMetricHeatmapLayout.rowCount
          let cellX = CGFloat(column) * (cellSize + spacing)
          let cellY = CGFloat(row) * (cellSize + spacing)
          let preferredX =
            column < DailyMetricHeatmapLayout.columnCount / 2
            ? cellX + cellSize + 8
            : cellX - hoverCardWidth - 8
          let cardX = min(max(0, preferredX), gridWidth - hoverCardWidth)
          let cardY = min(
            max(0, cellY + cellSize / 2 - hoverCardHeight / 2),
            gridHeight - hoverCardHeight
          )

          VStack(alignment: .leading, spacing: 3) {
            Text(
              hoveredCell.day.formatted(
                .dateTime.year().month().day().locale(language.locale)
              )
            )
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)

            HStack(spacing: 6) {
              Circle()
                .fill(color)
                .frame(width: 6, height: 6)
              Text(valueText(value))
                .font(.caption.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            }
          }
          .padding(.horizontal, 9)
          .frame(
            width: hoverCardWidth,
            height: hoverCardHeight,
            alignment: .leading
          )
          .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
          .overlay {
            RoundedRectangle(cornerRadius: 8)
              .stroke(SpellbookDesign.line, lineWidth: 1)
          }
          .shadow(color: .black.opacity(0.16), radius: 8, y: 3)
          .offset(x: cardX, y: cardY)
          .allowsHitTesting(false)
          .accessibilityHidden(true)
          .zIndex(1)
        }
      }
      .frame(width: gridWidth, height: gridHeight)

      ZStack(alignment: .leading) {
        ForEach(Array(monthMarkers.enumerated()), id: \.offset) { _, marker in
          Text(
            marker.day.formatted(
              .dateTime.month(.abbreviated).locale(language.locale)
            )
          )
          .font(.caption2)
          .foregroundStyle(.secondary)
          .offset(x: CGFloat(marker.column) * (cellSize + spacing))
        }
      }
      .frame(width: gridWidth, height: 14, alignment: .leading)
    }
    .frame(maxWidth: .infinity, alignment: .center)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityTitle)
    .accessibilityValue(accessibilitySummary)
  }

  private func fill(for cell: DailyMetricHeatmapCell) -> Color {
    if cell.value == nil { return SpellbookDesign.track.opacity(0.55) }
    if cell.isFuture { return SpellbookDesign.track.opacity(0.70) }
    guard cell.level > 0 else { return SpellbookDesign.track }
    return color.opacity([0, 0.25, 0.45, 0.70, 1][cell.level])
  }

  private func helpText(for cell: DailyMetricHeatmapCell) -> String {
    let date = cell.day.formatted(
      .dateTime.year().month().day().locale(language.locale)
    )
    guard let value = cell.value else {
      return language.text(.heatmapOutsidePeriodFormat, date)
    }
    if cell.isFuture { return language.text(.heatmapFutureFormat, date) }
    return "\(date), \(valueText(value))"
  }
}

private struct DailyMetricChart: View {
  let data: [DailyMetric]
  let color: Color
  let yAxisTitle: String
  let accessibilityTitle: String
  let valueText: (Double) -> String
  @Environment(\.appLanguage) private var language

  private var maximum: Double {
    max(Double.leastNonzeroMagnitude, data.map(\.value).max() ?? 0)
  }

  private var total: Double {
    data.reduce(0) { $0 + $1.value }
  }

  private var accessibilitySummary: String {
    data.map {
      "\($0.day.formatted(.dateTime.month().day().locale(language.locale))), \(valueText($0.value))"
    }.joined(separator: "; ")
  }

  var body: some View {
    ZStack {
      Chart(data) { item in
        AreaMark(
          x: .value(language.text(.chartDate), item.day, unit: .day),
          y: .value(yAxisTitle, item.value)
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
          x: .value(language.text(.chartDate), item.day, unit: .day),
          y: .value(yAxisTitle, item.value)
        )
        .interpolationMethod(.monotone)
        .foregroundStyle(color)
        .lineStyle(StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))

        if item.id == data.last?.id {
          PointMark(
            x: .value(language.text(.chartDate), item.day, unit: .day),
            y: .value(yAxisTitle, item.value)
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
          AxisValueLabel(format: .dateTime.month().day().locale(language.locale))
        }
      }
      .chartYAxis {
        AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
          AxisGridLine().foregroundStyle(SpellbookDesign.line)
          AxisValueLabel {
            if let metric = value.as(Double.self) {
              Text(valueText(metric))
            }
          }
        }
      }

      if total == 0 {
        Text(language.text(.chartNoRecords))
          .font(.caption)
          .foregroundStyle(.tertiary)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityTitle)
    .accessibilityValue(accessibilitySummary)
  }
}

private struct ModelRankingRow: View {
  let rank: Int
  let model: ModelIdentity
  let usage: TokenUsage
  let recordCount: Int
  let valueText: String
  @Environment(\.appLanguage) private var language

  private var source: String {
    [model.tool?.displayName, model.backend]
      .compactMap { $0 }
      .joined(separator: " · ")
  }

  private var cacheHitRate: Double { usage.cacheHitRate }

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
            Text(model.localizedDisplayName(language: language))
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
            Text(valueText)
              .font(.subheadline.weight(.semibold).monospacedDigit())
              .lineLimit(1)
              .minimumScaleFactor(0.5)
              .layoutPriority(1)
            Text(language.text(.rankingUsageRecordsFormat, recordCount))
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
        }

        HStack(spacing: 8) {
          Text(language.text(.cacheHit))
            .font(.caption)
            .foregroundStyle(.secondary)
          ProgressView(value: cacheHitRate)
            .tint(SpellbookDesign.success)
          Text(
            cacheHitRate.formatted(
              .percent.precision(.fractionLength(0)).locale(language.locale)
            )
          )
          .font(.caption.monospacedDigit())
          .frame(width: 38, alignment: .trailing)
        }
      }
    }
    .accessibilityElement(children: .combine)
  }
}
