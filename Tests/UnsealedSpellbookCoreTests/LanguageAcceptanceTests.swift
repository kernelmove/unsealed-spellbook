import Foundation
import Testing
import UnsealedSpellbookCore
import UnsealedSpellbookLanguage

@testable import UnsealedSpellbook

@Suite("Language catalogue")
struct LanguageAcceptanceTests {
  @Test("Every selectable language covers every UI and badge key")
  func completeCatalogue() {
    let achievements = UsageAnalytics(events: []).achievements

    for language in AppLanguage.allCases {
      for key in LanguageKey.allCases {
        #expect(language.translation(for: key.rawValue) != nil)
      }
      for achievement in achievements {
        #expect(language.translation(for: "achievement.\(achievement.id).title") != nil)
        #expect(language.translation(for: "achievement.\(achievement.id).detail") != nil)
      }
    }
  }

  @Test("The language selector exposes Simplified Chinese, Traditional Chinese, and US English")
  func supportedLanguages() {
    #expect(AppLanguage.allCases.map(\.rawValue) == ["zh-Hans", "zh-Hant", "en-US"])
    #expect(AppLanguage.simplifiedChinese.nativeName == "简体中文")
    #expect(AppLanguage.traditionalChinese.nativeName == "繁體中文")
    #expect(AppLanguage.english.nativeName == "English")
    #expect(AppLanguage.english.text(.navigationOverview) == "Overview")
    #expect(AppLanguage.traditionalChinese.text(.navigationAchievements) == "徽章")
  }

  @Test("The selected language is persisted and invalid values fall back safely")
  func persistedSelection() throws {
    let suiteName = "LanguageAcceptanceTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    #expect(AppPreferences.language(defaults: defaults) == .simplifiedChinese)
    defaults.set(AppLanguage.english.rawValue, forKey: AppPreferences.languageKey)
    #expect(AppPreferences.language(defaults: defaults) == .english)
    defaults.set("invalid", forKey: AppPreferences.languageKey)
    #expect(AppPreferences.language(defaults: defaults) == .simplifiedChinese)
  }
}
