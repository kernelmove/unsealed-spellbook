import Foundation

public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
  case simplifiedChinese = "zh-Hans"
  case traditionalChinese = "zh-Hant"
  case english = "en-US"

  public var id: Self { self }

  public var nativeName: String {
    switch self {
    case .simplifiedChinese: "简体中文"
    case .traditionalChinese: "繁體中文"
    case .english: "English"
    }
  }

  public var locale: Locale { Locale(identifier: rawValue) }

  public func translation(for key: String) -> String? {
    translations[key]
  }

  public func text(_ key: LanguageKey, _ arguments: CVarArg...) -> String {
    text(key.rawValue, arguments)
  }

  public func text(_ key: String, _ arguments: CVarArg...) -> String {
    text(key, arguments)
  }

  private func text(_ key: String, _ arguments: [CVarArg]) -> String {
    guard let format = translation(for: key) else { return key }
    guard !arguments.isEmpty else { return format }
    return String(format: format, locale: locale, arguments: arguments)
  }
}

public enum LanguageKey: String, CaseIterable, Sendable {
  case navigationOverview = "navigation.overview"
  case navigationAchievements = "navigation.achievements"
  case navigationSettings = "navigation.settings"
  case accessibilityPage = "accessibility.page"
  case actionRefreshUsage = "action.refreshUsage"
  case actionSwitchToLightMode = "action.switchToLightMode"
  case actionSwitchToDarkMode = "action.switchToDarkMode"
  case actionQuit = "action.quit"
  case loadingLocalLogs = "loading.localLogs"
  case loadingDescription = "loading.description"
  case periodToday = "period.today"
  case periodThisWeek = "period.thisWeek"
  case periodLast7Days = "period.last7Days"
  case periodLast30Days = "period.last30Days"
  case periodThisMonth = "period.thisMonth"
  case tierBronze = "tier.bronze"
  case tierSilver = "tier.silver"
  case tierGold = "tier.gold"
  case tierDiamond = "tier.diamond"
  case unknownModel = "model.unknown"
  case overviewTotalTokens = "overview.totalTokens"
  case overviewTotalCost = "overview.totalCost"
  case overviewAllTools = "overview.allTools"
  case overviewToolUsageShare = "overview.toolUsageShare"
  case overviewToolCostShare = "overview.toolCostShare"
  case overviewUnpricedFormat = "overview.unpricedFormat"
  case overviewDailyTrend = "overview.dailyTrend"
  case overviewAsOfFormat = "overview.asOfFormat"
  case perspectiveTokens = "perspective.tokens"
  case perspectiveCost = "perspective.cost"
  case actionOpenPricingRules = "action.openPricingRules"
  case toolDetails = "tool.details"
  case accessibilitySelectTool = "accessibility.selectTool"
  case metricTotal = "metric.total"
  case metricInput = "metric.input"
  case metricOutput = "metric.output"
  case metricCache = "metric.cache"
  case toolPeriodNote = "tool.periodNote"
  case toolDailyTrendFormat = "tool.dailyTrendFormat"
  case rankingToday = "ranking.today"
  case rankingDescription = "ranking.description"
  case rankingCostDescription = "ranking.costDescription"
  case rankingModelCountFormat = "ranking.modelCountFormat"
  case rankingEmpty = "ranking.empty"
  case accessibilityTimeRange = "accessibility.timeRange"
  case accessibilityProviderTokensFormat = "accessibility.providerTokensFormat"
  case accessibilityDailyHeatmap = "accessibility.dailyHeatmap"
  case heatmapOutsidePeriodFormat = "heatmap.outsidePeriodFormat"
  case heatmapFutureFormat = "heatmap.futureFormat"
  case heatmapTokensFormat = "heatmap.tokensFormat"
  case heatmapCostFormat = "heatmap.costFormat"
  case chartDate = "chart.date"
  case chartToken = "chart.token"
  case chartCost = "chart.cost"
  case chartNoRecords = "chart.noRecords"
  case accessibilityDailyTokenChart = "accessibility.dailyTokenChart"
  case accessibilityDailyCostChart = "accessibility.dailyCostChart"
  case rankingUsageRecordsFormat = "ranking.usageRecordsFormat"
  case cacheHit = "cache.hit"
  case settingsTitle = "settings.title"
  case settingsPrivacyDescription = "settings.privacyDescription"
  case settingsDataSources = "settings.dataSources"
  case settingsResidentBehavior = "settings.residentBehavior"
  case settingsShowMenuBarTotal = "settings.showMenuBarTotal"
  case settingsLaunchAtLogin = "settings.launchAtLogin"
  case settingsRefreshInterval = "settings.refreshInterval"
  case settingsOneMinute = "settings.oneMinute"
  case settingsFiveMinutes = "settings.fiveMinutes"
  case settingsFifteenMinutes = "settings.fifteenMinutes"
  case settingsLocalData = "settings.localData"
  case settingsStatus = "settings.status"
  case settingsUpdatedAtFormat = "settings.updatedAtFormat"
  case settingsNotScanned = "settings.notScanned"
  case settingsRefreshNow = "settings.refreshNow"
  case settingsDiagnosticsFormat = "settings.diagnosticsFormat"
  case settingsQuit = "settings.quit"
  case settingsLaunchApprovalRequired = "settings.launchApprovalRequired"
  case settingsLaunchUpdateFailedFormat = "settings.launchUpdateFailedFormat"
  case settingsLanguage = "settings.language"
  case settingsLanguageDescription = "settings.languageDescription"
  case settingsUpdates = "settings.updates"
  case settingsAutomaticallyCheckUpdates = "settings.automaticallyCheckUpdates"
  case settingsCheckUpdates = "settings.checkUpdates"
  case settingsCheckingUpdates = "settings.checkingUpdates"
  case settingsCurrentVersionFormat = "settings.currentVersionFormat"
  case settingsUpdateAvailableFormat = "settings.updateAvailableFormat"
  case settingsUpToDateFormat = "settings.upToDateFormat"
  case settingsOpenRelease = "settings.openRelease"
  case settingsUpdateCheckFailed = "settings.updateCheckFailed"
  case settingsManualUpdateDescription = "settings.manualUpdateDescription"
  case achievementStatusUnavailable = "achievement.status.unavailable"
  case achievementStatusUnlocked = "achievement.status.unlocked"
  case achievementStatusLocked = "achievement.status.locked"
  case achievementsTitle = "achievements.title"
  case achievementsSubtitle = "achievements.subtitle"
  case achievementsTotalTokens = "achievements.totalTokens"
  case achievementsActiveDays = "achievements.activeDays"
  case achievementsCurrentStreak = "achievements.currentStreak"
  case achievementsCacheHit = "achievements.cacheHit"
  case dayCountFormat = "count.daysFormat"
  case achievementsCollection = "achievements.collection"
  case achievementsLitCountFormat = "achievements.litCountFormat"
  case tierCollectionFormat = "achievement.tierCollectionFormat"
  case tierLitCountFormat = "achievement.tierLitCountFormat"
  case accessibilityExpanded = "accessibility.expanded"
  case accessibilityCollapsed = "accessibility.collapsed"
  case accessibilityCollapseBadges = "accessibility.collapseBadges"
  case accessibilityExpandBadges = "accessibility.expandBadges"
  case viewAchievementDetailsFormat = "achievement.viewDetailsFormat"
  case accessibilityOpenAchievementDetails = "accessibility.openAchievementDetails"
  case achievementProgressUnavailable = "achievement.progress.unavailable"
  case achievementProgressCompleted = "achievement.progress.completed"
  case achievementNoUnlockRecord = "achievement.noUnlockRecord"
  case achievementNotUnlocked = "achievement.notUnlocked"
  case achievementUnlockedPreview = "achievement.unlockedPreview"
  case achievementTierBadgeFormat = "achievement.tierBadgeFormat"
  case achievementProgress = "achievement.progress"
  case accessibilityUnlockProgress = "accessibility.unlockProgress"
  case achievementDescription = "achievement.description"
  case achievementUnlockDate = "achievement.unlockDate"
  case newAchievementUnlocked = "achievement.newUnlocked"
  case accessibilityNewAchievementCarousel = "accessibility.newAchievementCarousel"
  case actionAcceptAchievement = "action.acceptAchievement"
  case accessibilityAcceptNewAchievement = "accessibility.acceptNewAchievement"
  case accessibilityCloseNewAchievement = "accessibility.closeNewAchievement"
  case achievementCountFormat = "achievement.countFormat"
  case achievementCarouselPositionFormat = "achievement.carouselPositionFormat"
  case achievementPageFormat = "achievement.pageFormat"
  case achievementCountProgressFormat = "achievement.countProgressFormat"
  case achievementCacheProgressFormat = "achievement.cacheProgressFormat"
}
