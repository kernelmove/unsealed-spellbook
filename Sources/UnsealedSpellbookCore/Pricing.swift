import Foundation

public struct ModelPrice: Codable, Equatable, Sendable {
  public let model: String
  public let input: Double
  public let output: Double
  public let cacheRead: Double
  public let cacheWrite: Double
}

public struct UsageCost: Equatable, Sendable {
  public let input: Double
  public let output: Double
  public let cacheRead: Double
  public let cacheWrite: Double

  public var total: Double { input + output + cacheRead + cacheWrite }

  public static let zero = UsageCost(input: 0, output: 0, cacheRead: 0, cacheWrite: 0)

  static func + (lhs: UsageCost, rhs: UsageCost) -> UsageCost {
    UsageCost(
      input: lhs.input + rhs.input,
      output: lhs.output + rhs.output,
      cacheRead: lhs.cacheRead + rhs.cacheRead,
      cacheWrite: lhs.cacheWrite + rhs.cacheWrite
    )
  }
}

public enum PricingCatalogError: Error, Equatable {
  case invalidVersion
  case invalidCurrency
  case invalidUnit
  case invalidModel(String)
  case duplicateModel(String)
  case invalidRate(String)
  case missingBundledResource
}

public struct PricingCatalog: Sendable {
  public let version: Int
  public let currency: String
  public let unit: Double
  private let prices: [String: ModelPrice]

  public var modelCount: Int { prices.count }

  public init(data: Data) throws {
    let document: PricingDocument
    do {
      document = try JSONDecoder().decode(PricingDocument.self, from: data)
    } catch {
      throw PricingCatalogError.invalidVersion
    }
    guard document.version > 0 else { throw PricingCatalogError.invalidVersion }
    guard document.currency == "USD" else { throw PricingCatalogError.invalidCurrency }
    guard document.unit > 0 else { throw PricingCatalogError.invalidUnit }

    var indexed: [String: ModelPrice] = [:]
    for price in document.models {
      let name = price.model.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !name.isEmpty, name == price.model else {
        throw PricingCatalogError.invalidModel(price.model)
      }
      let key = name.lowercased()
      guard indexed[key] == nil else { throw PricingCatalogError.duplicateModel(name) }
      let rates = [price.input, price.output, price.cacheRead, price.cacheWrite]
      guard rates.allSatisfy({ $0.isFinite && $0 >= 0 }) else {
        throw PricingCatalogError.invalidRate(name)
      }
      indexed[key] = price
    }

    version = document.version
    currency = document.currency
    unit = document.unit
    prices = indexed
  }

  public static func bundled() throws -> PricingCatalog {
    for bundle in [Bundle.main, Bundle.module] {
      if let url = bundle.url(forResource: "model-pricing", withExtension: "json") {
        return try PricingCatalog(data: Data(contentsOf: url))
      }
    }
    throw PricingCatalogError.missingBundledResource
  }

  public func price(for model: ModelIdentity) -> ModelPrice? {
    guard model.isKnown else { return nil }
    return prices[model.name.lowercased()]
  }

  public func cost(for usage: TokenUsage, model: ModelIdentity) -> UsageCost? {
    guard let price = price(for: model) else { return nil }
    return UsageCost(
      input: Double(usage.input) / unit * price.input,
      output: (Double(usage.output) + Double(usage.reasoning)) / unit * price.output,
      cacheRead: Double(usage.cacheRead) / unit * price.cacheRead,
      cacheWrite: Double(usage.cacheWrite) / unit * price.cacheWrite
    )
  }
}

public struct CostSnapshot: Sendable {
  public let interval: DateInterval
  public let providers: [AIProvider: UsageCost]
  public let total: UsageCost
  public let unpricedModels: Set<String>
  public let unpricedTokens: Int
}

public struct DailyCost: Identifiable, Sendable {
  public let day: Date
  public let cost: UsageCost
  public let unpricedTokens: Int
  public var id: Date { day }
}

public struct ModelCostSummary: Identifiable, Sendable {
  public let model: ModelIdentity
  public let usage: TokenUsage
  public let cost: UsageCost?
  public let recordCount: Int
  public var id: ModelIdentity { model }
}

extension UsageAnalytics {
  public func costSnapshot(
    for period: UsagePeriod,
    provider: AIProvider? = nil,
    catalog: PricingCatalog
  ) -> CostSnapshot {
    let interval = period.interval(containing: now, calendar: calendar)
    var providers: [AIProvider: UsageCost] = [:]
    var total = UsageCost.zero
    var unpricedModels: Set<String> = []
    var unpricedTokens = 0

    for event in events where matches(event, interval: interval, provider: provider) {
      guard let cost = catalog.cost(for: event.usage, model: event.model) else {
        unpricedModels.insert(event.model.name)
        unpricedTokens += event.usage.total
        continue
      }
      providers[event.provider, default: .zero] = providers[event.provider, default: .zero] + cost
      total = total + cost
    }

    return CostSnapshot(
      interval: interval,
      providers: providers,
      total: total,
      unpricedModels: unpricedModels,
      unpricedTokens: unpricedTokens
    )
  }

  public func dailyCost(
    for period: UsagePeriod,
    provider: AIProvider? = nil,
    catalog: PricingCatalog
  ) -> [DailyCost] {
    let interval = period.interval(containing: now, calendar: calendar)
    var totals: [Date: UsageCost] = [:]
    var unpriced: [Date: Int] = [:]
    for event in events where matches(event, interval: interval, provider: provider) {
      let day = calendar.startOfDay(for: event.timestamp)
      if let cost = catalog.cost(for: event.usage, model: event.model) {
        totals[day, default: .zero] = totals[day, default: .zero] + cost
      } else {
        unpriced[day, default: 0] += event.usage.total
      }
    }

    var result: [DailyCost] = []
    var day = calendar.startOfDay(for: interval.start)
    while day < interval.end {
      result.append(
        DailyCost(
          day: day,
          cost: totals[day] ?? .zero,
          unpricedTokens: unpriced[day] ?? 0
        ))
      day = calendar.date(byAdding: .day, value: 1, to: day)!
    }
    return result
  }

  public func modelCostRankings(
    for period: UsagePeriod,
    provider: AIProvider? = nil,
    catalog: PricingCatalog
  ) -> [ModelCostSummary] {
    let interval = period.interval(containing: now, calendar: calendar)
    var grouped: [ModelIdentity: (usage: TokenUsage, records: Int)] = [:]
    for event in events where matches(event, interval: interval, provider: provider) {
      let current = grouped[event.model] ?? (.zero, 0)
      grouped[event.model] = (current.usage + event.usage, current.records + 1)
    }

    return grouped.map { model, value in
      ModelCostSummary(
        model: model,
        usage: value.usage,
        cost: catalog.cost(for: value.usage, model: model),
        recordCount: value.records
      )
    }.sorted {
      switch ($0.cost, $1.cost) {
      case (.some(let lhs), .some(let rhs)) where lhs.total != rhs.total:
        return lhs.total > rhs.total
      case (.some, .none):
        return true
      case (.none, .some):
        return false
      default:
        return $0.model.displayName < $1.model.displayName
      }
    }
  }

  private func matches(
    _ event: UsageEvent,
    interval: DateInterval,
    provider: AIProvider?
  ) -> Bool {
    event.timestamp >= interval.start && event.timestamp < interval.end
      && (provider == nil || event.provider == provider)
  }
}

private struct PricingDocument: Decodable {
  let version: Int
  let currency: String
  let unit: Double
  let models: [ModelPrice]
}
