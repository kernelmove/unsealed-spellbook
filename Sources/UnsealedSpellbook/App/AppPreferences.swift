import Foundation
import UnsealedSpellbookCore
import UnsealedSpellbookLanguage

enum AppPreferences {
  private static let updateCheckInterval: TimeInterval = 24 * 60 * 60

  static let refreshIntervalKey = "refreshIntervalSeconds"
  static let showMenuBarTotalKey = "showMenuBarTotal"
  static let automaticallyCheckForUpdatesKey = "automaticallyCheckForUpdates"
  static let lastUpdateCheckKey = "lastUpdateCheck"
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

  static func shouldAutomaticallyCheckForUpdates(
    now: Date = Date(),
    defaults: UserDefaults = .standard
  ) -> Bool {
    automaticUpdateCheckDelay(now: now, defaults: defaults) == 0
  }

  static func automaticallyCheckForUpdates(defaults: UserDefaults = .standard) -> Bool {
    defaults.object(forKey: automaticallyCheckForUpdatesKey) as? Bool ?? true
  }

  static func automaticUpdateCheckDelay(
    now: Date = Date(),
    defaults: UserDefaults = .standard
  ) -> TimeInterval? {
    guard automaticallyCheckForUpdates(defaults: defaults) else { return nil }
    guard let lastCheck = defaults.object(forKey: lastUpdateCheckKey) as? Date else { return 0 }
    let elapsed = max(0, now.timeIntervalSince(lastCheck))
    return max(0, updateCheckInterval - elapsed)
  }

  static func recordUpdateCheck(
    at date: Date = Date(),
    defaults: UserDefaults = .standard
  ) {
    defaults.set(date, forKey: lastUpdateCheckKey)
  }

  static func language(defaults: UserDefaults = .standard) -> AppLanguage {
    let code = defaults.string(forKey: languageKey)
    return code.flatMap(AppLanguage.init(rawValue:)) ?? .simplifiedChinese
  }
}
