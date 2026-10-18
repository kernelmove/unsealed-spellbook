import Charts
import SwiftUI
import UnsealedSpellbookCore
import UnsealedSpellbookLanguage

struct DetailDashboardView: View {
  let analytics: UsageAnalytics
  let pricingCatalog: PricingCatalog?
  let enabledProviders: Set<AIProvider>

  @State private var period: UsagePeriod = .last7Days
  @State private var selectedProvider: AIProvider
  @State private var perspective: UsagePerspective

  init(
    analytics: UsageAnalytics,
    pricingCatalog: PricingCatalog?,
    enabledProviders: Set<AIProvider> = Set(AIProvider.allCases),
    initialPerspective: UsagePerspective = .tokens
  ) {
    self.analytics = analytics
    self.pricingCatalog = pricingCatalog
    self.enabledProviders = enabledProviders
    _selectedProvider = State(
      initialValue: enabledProviders.contains(.codex)
        ? .codex
        : AIProvider.allCases.first(where: enabledProviders.contains) ?? .codex
    )
    _perspective = State(initialValue: initialPerspective)
  }

  private var providers: [AIProvider] {
    AIProvider.allCases.filter(enabledProviders.contains)
  }

  var body: some View {
    ScrollView {
      VStack(spacing: SpellbookDesign.spacing) {
        HStack(spacing: 8) {
          Text(language.text(.navigationOverview))
            .font(.title2.weight(.semibold))
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

        TotalUsagePanel(
          analytics: analytics,
          catalog: pricingCatalog,
          providers: providers,
          perspective: perspective,
          period: $period
        )

        if !providers.isEmpty {
          ToolDetailPanel(
            analytics: analytics,
            catalog: pricingCatalog,
            providers: providers,
            perspective: perspective,
            provider: $selectedProvider,
            period: period
          )
        }

        ModelRankingPanel(
          analytics: analytics,
          catalog: pricingCatalog,
          perspective: perspective
        )
      }
      .padding(SpellbookDesign.spacing)
    }
    .background(SpellbookDesign.surfaceSoft)
    .onChange(of: enabledProviders) {
      if !enabledProviders.contains(selectedProvider), let provider = providers.first {
        selectedProvider = provider
      }
    }
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
  let providers: [AIProvider]
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
        ForEach(providers, id: \.rawValue) { provider in
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

      DailyMetricChart(
        data: perspective == .tokens
          ? dailyUsage.map { DailyMetric(day: $0.day, value: Double($0.usage.total)) }
          : dailyCost.map { DailyMetric(day: $0.day, value: $0.cost.total) },
        color: SpellbookDesign.metricBlue,
        yAxisTitle: language.text(perspective == .tokens ? .chartToken : .chartCost),
        accessibilityTitle: language.text(
          perspective == .tokens
            ? .accessibilityDailyTokenChart : .accessibilityDailyCostChart
        ),
        valueText: { value in
          if perspective == .tokens {
            return Int(value).formatted(.number.locale(language.locale)) + " Token"
          }
          return value.compactUSDCost()
        }
      )
      .frame(height: 150)
    }
    .padding(.vertical, 24)
    .padding(.horizontal, 24)
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

struct ToolDetailPanel: View {
  let analytics: UsageAnalytics
  let catalog: PricingCatalog?
  let providers: [AIProvider]
  let perspective: UsagePerspective
  @Binding var provider: AIProvider
  let period: UsagePeriod
  @Environment(\.appLanguage) private var language
  @Environment(\.colorScheme) private var colorScheme

  private let columns = [
    GridItem(.flexible(), spacing: 10),
    GridItem(.flexible(), spacing: 10),
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

    VStack(alignment: .leading, spacing: 14) {
      Text(language.text(.toolDetails))
        .font(.system(size: 18, weight: .semibold))

      providerPicker

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

      Divider()
        .overlay(SpellbookDesign.line)
        .padding(.top, 6)

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
      .frame(height: 150)
    }
    .padding(24)
    .spellbookPanel()
  }

  private var providerPicker: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 4) {
        ForEach(providers, id: \.rawValue) { option in
          Button {
            provider = option
          } label: {
            HStack(spacing: 7) {
              ProviderIcon(option, size: 20)
              Text(shortName(option))
                .lineLimit(1)
            }
            .font(.system(size: 12, weight: option == provider ? .semibold : .medium))
            .foregroundStyle(option == provider ? Color.primary : Color.secondary)
            .padding(.horizontal, 10)
            .frame(minHeight: 34)
            .contentShape(Rectangle())
          }
          .buttonStyle(SpellbookPressButtonStyle())
          .background {
            if option == provider {
              RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                  option.tintColor.opacity(colorScheme == .dark ? 0.22 : 0.12)
                )
            }
          }
          .overlay {
            if option == provider {
              RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(option.tintColor.opacity(0.28), lineWidth: 1)
            }
          }
          .accessibilityLabel(option.displayName)
        }
      }
      .padding(4)
      .background(
        SpellbookDesign.segmentedBackground,
        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
      )
    }
    .accessibilityLabel(language.text(.accessibilitySelectTool))
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
        ProviderIcon(provider, size: 26)
        Text(provider.displayName)
          .font(.subheadline)
          .lineLimit(1)
      }
      .frame(width: 154, alignment: .leading)

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
    .frame(maxWidth: .infinity, minHeight: 106, alignment: .leading)
    .background(
      SpellbookDesign.surfaceSoft,
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
            colors: [color.opacity(0.18), color.opacity(0)],
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
        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

        if item.id == data.last?.id {
          PointMark(
            x: .value(language.text(.chartDate), item.day, unit: .day),
            y: .value(yAxisTitle, item.value)
          )
          .foregroundStyle(SpellbookDesign.surface)
          .symbolSize(48)
          .annotation(position: .overlay) {
            Circle()
              .stroke(color, lineWidth: 3)
              .frame(width: 9, height: 9)
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
          .foregroundStyle(.secondary)
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
