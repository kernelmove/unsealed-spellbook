import Foundation
import Observation
import UnsealedSpellbookCore

@MainActor
@Observable
final class UsageStore {
  private(set) var analytics: UsageAnalytics?
  private(set) var snapshot: UsageSnapshot?
  private(set) var diagnostics: CollectionDiagnostics?
  private(set) var lastUpdated: Date?
  private(set) var isRefreshing = false
  private var isLoopRunning = false
  private var refreshQueued = false
  private let collector: LocalUsageCollector

  init(collector: LocalUsageCollector = LocalUsageCollector()) {
    self.collector = collector
  }

  var menuBarTotal: String {
    guard let total = snapshot?.total.total else { return "—" }
    return total.formatted(.number.notation(.compactName))
  }

  func refresh() async {
    guard !isRefreshing else {
      refreshQueued = true
      return
    }
    isRefreshing = true
    defer { isRefreshing = false }

    repeat {
      refreshQueued = false
      await collectUsage()
    } while refreshQueued && !Task.isCancelled
  }

  private func collectUsage() async {
    let result = await collector.collect(
      interval: DateInterval(start: .distantPast, end: .distantFuture),
      enabledProviders: AppPreferences.enabledProviders()
    )
    let latestAnalytics = UsageAnalytics(events: result.events)
    analytics = latestAnalytics
    snapshot = latestAnalytics.snapshot(for: .today)
    diagnostics = result.diagnostics
    lastUpdated = Date()
  }

  func runRefreshLoop() async {
    guard !isLoopRunning else { return }
    isLoopRunning = true
    defer { isLoopRunning = false }

    while !Task.isCancelled {
      await refresh()
      do {
        try await Task.sleep(for: AppPreferences.refreshInterval())
      } catch {
        return
      }
    }
  }
}
