import Foundation
import UnsealedSpellbookCore
import UnsealedSpellbookLanguage

enum AppPreferences {
  static let refreshIntervalKey = "refreshIntervalSeconds"
  static let showMenuBarTotalKey = "showMenuBarTotal"
  static let languageKey = "appLanguage"
  static let acknowledgedAchievementsKey = "acknowledgedAchievementIDs"
  static let achievementUnlockRecordsKey = "achievementUnlockRecords"

  static func providerKey(_ provider: AIProvider) -> String {
    "provider.\(provider.rawValue).enabled"
  }

  static func enabledProviders(defaults: UserDefaults = .standard) -> Set<AIProvider> {
    Set(
      AIProvider.allCases.filter { provider in
        let key = providerKey(provider)
        return defaults.object(forKey: key) as? Bool ?? true
      })
  }

  static func refreshInterval(defaults: UserDefaults = .standard) -> Duration {
    let seconds = defaults.object(forKey: refreshIntervalKey) as? Double ?? 300
    guard [60.0, 300.0, 900.0].contains(seconds) else { return .seconds(60) }
    return .seconds(seconds)
  }

  static func showMenuBarTotal(defaults: UserDefaults = .standard) -> Bool {
    defaults.object(forKey: showMenuBarTotalKey) as? Bool ?? true
  }

  static func language(defaults: UserDefaults = .standard) -> AppLanguage {
    let code = defaults.string(forKey: languageKey)
    return code.flatMap(AppLanguage.init(rawValue:)) ?? .simplifiedChinese
  }
}
