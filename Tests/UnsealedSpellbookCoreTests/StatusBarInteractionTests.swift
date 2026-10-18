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
    #expect(SpellbookDesign.minimumWindowSize == CGSize(width: 840, height: 620))
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

  @Test("Saving data sources replaces the complete provider selection")
  func providerPreferences() throws {
    let suiteName = "UnsealedSpellbookTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    #expect(AppPreferences.enabledProviders(defaults: defaults) == Set(AIProvider.allCases))

    AppPreferences.setEnabledProviders([.openClaude, .codex], defaults: defaults)
    #expect(AppPreferences.enabledProviders(defaults: defaults) == [.openClaude, .codex])

    AppPreferences.setEnabledProviders([], defaults: defaults)
    #expect(AppPreferences.enabledProviders(defaults: defaults).isEmpty)
  }

}
