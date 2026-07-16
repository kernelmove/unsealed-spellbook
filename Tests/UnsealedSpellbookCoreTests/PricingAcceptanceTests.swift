import Foundation
import Testing

@testable import UnsealedSpellbookCore

@Suite("Model pricing")
struct PricingAcceptanceTests {
  @Test("PDF formula prices exclusive token buckets without double counting reasoning")
  func formula() throws {
    let catalog = try PricingCatalog(
      data: Data(
        #"{"version":1,"currency":"USD","unit":1000000,"models":[{"model":"gpt-test","input":2,"output":10,"cacheRead":0.2,"cacheWrite":2.5}]}"#
          .utf8
      ))
    let usage = TokenUsage(
      input: 1_000_000,
      output: 2_000_000,
      cacheRead: 3_000_000,
      cacheWrite: 4_000_000,
      reasoning: 500_000,
      total: 10_500_000
    )

    let cost = try #require(catalog.cost(for: usage, model: ModelIdentity(name: "gpt-test")))

    #expect(cost.input == 2)
    #expect(cost.output == 25)
    #expect(abs(cost.cacheRead - 0.6) < 0.000_000_1)
    #expect(cost.cacheWrite == 10)
    #expect(abs(cost.total - 37.6) < 0.000_000_1)
  }

  @Test("Pricing is exact by model name, ignores reasoning variant, and reports unknown models")
  func exactMatching() throws {
    let catalog = try PricingCatalog(
      data: Data(
        #"{"version":1,"currency":"USD","unit":1000000,"models":[{"model":"gpt-test","input":1,"output":2,"cacheRead":0,"cacheWrite":0}]}"#
          .utf8
      ))
    let usage = TokenUsage(input: 10, output: 5, total: 15)

    #expect(
      catalog.cost(
        for: usage,
        model: ModelIdentity(name: "GPT-TEST", variant: "xhigh")
      ) != nil
    )
    #expect(catalog.cost(for: usage, model: ModelIdentity(name: "gpt-test-new")) == nil)
  }

  @Test("Invalid and duplicate pricing rules are rejected")
  func validation() {
    let duplicate = Data(
      #"{"version":1,"currency":"USD","unit":1000000,"models":[{"model":"gpt-test","input":1,"output":2,"cacheRead":0,"cacheWrite":0},{"model":"GPT-TEST","input":1,"output":2,"cacheRead":0,"cacheWrite":0}]}"#
        .utf8
    )
    let negative = Data(
      #"{"version":1,"currency":"USD","unit":1000000,"models":[{"model":"gpt-test","input":-1,"output":2,"cacheRead":0,"cacheWrite":0}]}"#
        .utf8
    )

    #expect(throws: PricingCatalogError.self) { try PricingCatalog(data: duplicate) }
    #expect(throws: PricingCatalogError.self) { try PricingCatalog(data: negative) }
  }

  @Test("Cost analytics preserve provider, day, and unpriced-model visibility")
  func analytics() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let now = try #require(ISO8601DateFormatter().date(from: "2026-07-15T12:00:00Z"))
    let catalog = try PricingCatalog(
      data: Data(
        #"{"version":1,"currency":"USD","unit":1000000,"models":[{"model":"priced","input":1,"output":2,"cacheRead":0,"cacheWrite":0}]}"#
          .utf8
      ))
    let events = [
      UsageEvent(
        id: "priced",
        provider: .codex,
        timestamp: now,
        usage: TokenUsage(input: 1_000_000, output: 1_000_000, total: 2_000_000),
        model: ModelIdentity(tool: .codex, name: "priced")
      ),
      UsageEvent(
        id: "unknown",
        provider: .openCode,
        timestamp: now,
        usage: TokenUsage(input: 500, output: 500, total: 1_000),
        model: ModelIdentity(tool: .openCode, name: "unknown-price")
      ),
    ]
    let analytics = UsageAnalytics(events: events, now: now, calendar: calendar)

    let snapshot = analytics.costSnapshot(for: .today, catalog: catalog)
    let daily = analytics.dailyCost(for: .today, catalog: catalog)

    #expect(snapshot.total.total == 3)
    #expect(snapshot.providers[.codex]?.total == 3)
    #expect(snapshot.unpricedModels == ["unknown-price"])
    #expect(snapshot.unpricedTokens == 1_000)
    #expect(daily.count == 1)
    #expect(daily.first?.cost.total == 3)
    #expect(daily.first?.unpricedTokens == 1_000)
  }

  @Test("Bundled PDF catalogue loads with representative model prices")
  func bundledCatalogue() throws {
    let catalog = try PricingCatalog.bundled()

    #expect(catalog.modelCount == 98)
    #expect(catalog.price(for: ModelIdentity(name: "gpt-5.6-sol"))?.output == 30)
    #expect(catalog.price(for: ModelIdentity(name: "gemini-3.1-pro-preview"))?.input == 2)
    #expect(catalog.price(for: ModelIdentity(name: "MiniMax-M2"))?.cacheWrite == 0)
  }
}
