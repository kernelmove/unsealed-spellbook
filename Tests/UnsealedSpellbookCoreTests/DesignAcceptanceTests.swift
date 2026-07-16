import AppKit
import SwiftUI
import Testing
import UnsealedSpellbookCore
import UnsealedSpellbookLanguage

@testable import UnsealedSpellbook

@Suite("Design rendering")
struct DesignAcceptanceTests {
  @Test("US dollar amounts use compact international units without losing small values")
  func compactCostFormatting() {
    #expect(0.0.compactUSDCost() == "$0.00")
    #expect(0.000_001.compactUSDCost() == "$0.000001")
    #expect(100.0.compactUSDCost() == "$100.00")
    #expect(999.99.compactUSDCost() == "$999.99")
    #expect(1_000.0.compactUSDCost() == "$1K")
    #expect(10_000.0.compactUSDCost() == "$10K")
    #expect(100_000.0.compactUSDCost() == "$100K")
    #expect(12_500.0.compactUSDCost() == "$12.5K")
    #expect(999_999.0.compactUSDCost() == "$1M")
    #expect(1_000_000.0.compactUSDCost() == "$1M")
    #expect(10_000_000.0.compactUSDCost() == "$10M")
    #expect(100_000_000.0.compactUSDCost() == "$100M")
    #expect(1_000_000_000.0.compactUSDCost() == "$1B")
    #expect(1_000_000_000_000.0.compactUSDCost() == "$1T")
  }

  @Test("Overview, achievements, settings, and dark mode render at the prototype size")
  @MainActor
  func designScreens() async throws {
    let previousLanguage = UserDefaults.standard.string(forKey: AppPreferences.languageKey)
    UserDefaults.standard.set(
      snapshotLanguage.rawValue,
      forKey: AppPreferences.languageKey
    )
    defer {
      if let previousLanguage {
        UserDefaults.standard.set(previousLanguage, forKey: AppPreferences.languageKey)
      } else {
        UserDefaults.standard.removeObject(forKey: AppPreferences.languageKey)
      }
    }

    let fixtureRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: fixtureRoot) }

    let codexDirectory = fixtureRoot.appendingPathComponent("codex", isDirectory: true)
    try FileManager.default.createDirectory(at: codexDirectory, withIntermediateDirectories: true)
    try codexFixture.write(
      to: codexDirectory.appendingPathComponent("usage.jsonl"),
      atomically: true,
      encoding: .utf8
    )

    let locations = LocalUsageLocations(
      claudeCodeDirectory: fixtureRoot.appendingPathComponent("claude"),
      codexDirectory: codexDirectory,
      openCodeDatabase: fixtureRoot.appendingPathComponent("opencode.db")
    )
    let store = UsageStore(collector: LocalUsageCollector(locations: locations))
    await store.refresh()
    let navigation = DashboardNavigation()
    let modalAchievements = Array(
      store.analytics?.achievements.filter(\.isUnlocked).prefix(3) ?? []
    )
    let detailAchievement = try #require(modalAchievements.first)
    let detailUnlockDate = try #require(
      ISO8601DateFormatter().date(from: "2026-07-12T12:00:00Z")
    )
    let detailRecord = AchievementUnlockRecord(
      id: detailAchievement.id,
      criteriaVersion: detailAchievement.criteriaVersion,
      unlockedAt: detailUnlockDate,
      unlockValue: detailAchievement.progressLabel
    )
    let silverAchievement = try #require(
      store.analytics?.achievements.first { $0.tier == .silver && $0.isVisible }
    )
    let analytics = try #require(store.analytics)
    let pricingCatalog = try #require(store.pricingCatalog)
    let largeCostAnalytics = UsageAnalytics(
      events: [
        UsageEvent(
          id: "large-cost-layout",
          provider: .codex,
          timestamp: analytics.now,
          usage: TokenUsage(
            input: 1_000_000_000_000,
            output: 0,
            total: 1_000_000_000_000
          ),
          model: ModelIdentity(tool: .codex, name: "gpt-5.6-sol")
        )
      ],
      now: analytics.now,
      calendar: analytics.calendar
    )
    #expect(
      largeCostAnalytics.costSnapshot(
        for: .last7Days,
        catalog: pricingCatalog
      ).total.total == 5_000_000
    )

    let screens: [(String, NSImage?)] = [
      (
        "overview-light",
        render(store: store, navigation: navigation, page: .details, scheme: .light)
      ),
      (
        "overview-dark", render(store: store, navigation: navigation, page: .details, scheme: .dark)
      ),
      (
        "overview-cost-light",
        snapshot(
          of: DetailDashboardView(
            analytics: largeCostAnalytics,
            pricingCatalog: pricingCatalog,
            initialPerspective: .cost
          ),
          scheme: .light
        )
      ),
      (
        "achievements-light",
        render(store: store, navigation: navigation, page: .achievements, scheme: .light)
      ),
      (
        "achievement-modal-light",
        renderModal(achievements: modalAchievements, scheme: .light)
      ),
      (
        "achievement-modal-dark",
        renderModal(achievements: modalAchievements, scheme: .dark)
      ),
      (
        "achievement-detail-light",
        renderDetail(
          achievement: detailAchievement,
          record: detailRecord,
          scheme: .light
        )
      ),
      (
        "achievement-detail-dark",
        renderDetail(
          achievement: detailAchievement,
          record: detailRecord,
          scheme: .dark
        )
      ),
      (
        "silver-contrast-light",
        renderSilverContrast(achievement: silverAchievement, scheme: .light)
      ),
      (
        "silver-contrast-dark",
        renderSilverContrast(achievement: silverAchievement, scheme: .dark)
      ),
      (
        "achievements-dark",
        render(store: store, navigation: navigation, page: .achievements, scheme: .dark)
      ),
      (
        "settings-light",
        render(store: store, navigation: navigation, page: .settings, scheme: .light)
      ),
      (
        "settings-dark",
        render(store: store, navigation: navigation, page: .settings, scheme: .dark)
      ),
    ]

    #expect(screens.allSatisfy { $0.1 != nil })
    if let outputPath = ProcessInfo.processInfo.environment["UNSEALED_SNAPSHOT_DIR"] {
      let output = URL(fileURLWithPath: outputPath, isDirectory: true)
      try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
      for (name, image) in screens {
        try pngData(image).write(to: output.appendingPathComponent("\(name).png"))
      }
    }
  }

  @MainActor
  private func render(
    store: UsageStore,
    navigation: DashboardNavigation,
    page: DashboardPage,
    scheme: ColorScheme
  ) -> NSImage? {
    navigation.selectedPage = page
    return snapshot(
      of: UsageMenuView(
        store: store,
        updateStore: GitHubReleaseStore(currentVersion: "1.0.1"),
        navigation: navigation
      ),
      scheme: scheme
    )
  }

  @MainActor
  private func renderModal(
    achievements: [Achievement],
    scheme: ColorScheme
  ) -> NSImage? {
    snapshot(
      of: ZStack {
        Color.black.opacity(0.48)
        NewAchievementModal(achievements: achievements) {}
      },
      scheme: scheme
    )
  }

  @MainActor
  private func renderDetail(
    achievement: Achievement,
    record: AchievementUnlockRecord,
    scheme: ColorScheme
  ) -> NSImage? {
    snapshot(
      of: ZStack {
        Color.black.opacity(0.48)
        AchievementDetailPopover(
          achievement: achievement,
          isUnlocked: true,
          unlockRecord: record
        )
        .background(SpellbookDesign.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).stroke(SpellbookDesign.line) }
        .shadow(color: .black.opacity(0.24), radius: 24, y: 12)
      },
      scheme: scheme
    )
  }

  @MainActor
  private func renderSilverContrast(
    achievement: Achievement,
    scheme: ColorScheme
  ) -> NSImage? {
    snapshot(
      of: ZStack {
        SpellbookDesign.surfaceSoft

        VStack(spacing: 20) {
          Text("银色徽章状态对比")
            .font(.title3.weight(.semibold))

          HStack(spacing: 32) {
            VStack(spacing: 10) {
              AchievementArtwork(achievement: achievement, isUnlocked: false, size: 140)
              Text("未解锁")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
              AchievementArtwork(achievement: achievement, isUnlocked: true, size: 140)
              Text("已解锁")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(achievement.tier.tintColor)
            }
          }
        }
        .padding(28)
        .background(SpellbookDesign.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).stroke(SpellbookDesign.line) }
      },
      scheme: scheme
    )
  }

  @MainActor
  private func snapshot<Content: View>(
    of content: Content,
    scheme: ColorScheme
  ) -> NSImage? {
    let view = NSHostingView(
      rootView:
        content
        .environment(\.appLanguage, snapshotLanguage)
        .environment(\.locale, snapshotLanguage.locale)
        .preferredColorScheme(scheme)
    )
    view.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
    view.frame = NSRect(origin: .zero, size: SpellbookDesign.windowSize)
    view.layoutSubtreeIfNeeded()

    guard let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
      return nil
    }
    view.cacheDisplay(in: view.bounds, to: representation)
    let image = NSImage(size: SpellbookDesign.windowSize)
    image.addRepresentation(representation)
    return image
  }

  private func pngData(_ image: NSImage?) throws -> Data {
    guard
      let image,
      let tiff = image.tiffRepresentation,
      let representation = NSBitmapImageRep(data: tiff),
      let png = representation.representation(using: .png, properties: [:])
    else {
      throw CocoaError(.fileWriteUnknown)
    }
    return png
  }

  private var snapshotLanguage: AppLanguage {
    ProcessInfo.processInfo.environment["UNSEALED_SNAPSHOT_LANGUAGE"]
      .flatMap(AppLanguage.init(rawValue:)) ?? .english
  }

  private var codexFixture: String {
    let context =
      #"{"timestamp":"2026-07-12T01:02:02Z","type":"turn_context","payload":{"model":"gpt-5.6-sol","effort":"xhigh"}}"#
    let usage =
      #"{"timestamp":"2026-07-12T01:02:03Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":145000000,"cached_input_tokens":140000000,"output_tokens":5000000,"reasoning_output_tokens":1000000,"total_tokens":150000000},"total_token_usage":{"input_tokens":145000000,"cached_input_tokens":140000000,"output_tokens":5000000,"reasoning_output_tokens":1000000,"total_tokens":150000000}}}}"#
    return "\(context)\n\(usage)\n"
  }
}
