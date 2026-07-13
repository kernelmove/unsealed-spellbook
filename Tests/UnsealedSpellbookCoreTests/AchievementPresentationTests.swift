import AppKit
import Foundation
import Testing
import UnsealedSpellbookCore
import UnsealedSpellbookLanguage

@testable import UnsealedSpellbook

@Suite("Achievement presentation")
struct AchievementPresentationTests {
  @Test("New badges are filtered and ordered from rare to common")
  func newBadgeOrdering() {
    let event = UsageEvent(
      id: "usage",
      provider: .codex,
      timestamp: Date(),
      usage: TokenUsage(input: 1_000_000_000_000, output: 0, total: 1_000_000_000_000)
    )
    let achievements = UsageAnalytics(events: [event]).achievements
    let acknowledged = Set(achievements.filter(\.isUnlocked).map(\.id))
      .subtracting(["trillion-tokens", "ten-billion-tokens"])

    let unseen = AchievementPresentation.unseen(
      in: achievements,
      acknowledgedIDs: acknowledged
    )

    #expect(unseen.map(\.id) == ["trillion-tokens", "ten-billion-tokens"])
    #expect(
      AchievementPresentation.tierOrder.map(\.rawValue) == [
        "diamond", "gold", "silver", "bronze",
      ])
  }

  @Test("Persisting the same unlocked badges twice creates no new records")
  func idempotentUnlockPersistence() {
    let event = UsageEvent(
      id: "usage",
      provider: .codex,
      timestamp: Date(),
      usage: TokenUsage(input: 10_000_000_000, output: 0, total: 10_000_000_000)
    )
    let achievements = UsageAnalytics(events: [event]).achievements
    let now = Date(timeIntervalSince1970: 1_000)

    let first = AchievementUnlockPersistence.merge(
      records: [],
      achievements: achievements,
      now: now
    )
    let second = AchievementUnlockPersistence.merge(
      records: first.records,
      achievements: achievements,
      now: now.addingTimeInterval(3_600)
    )
    let afterSourceRemoval = AchievementUnlockPersistence.merge(
      records: first.records,
      achievements: UsageAnalytics(events: []).achievements,
      now: now
    )

    #expect(!first.newlyUnlocked.isEmpty)
    #expect(first.records.allSatisfy { $0.unlockedAt == now })
    #expect(second.newlyUnlocked.isEmpty)
    #expect(second.records == first.records)
    #expect(afterSourceRemoval.newlyUnlocked.isEmpty)
    #expect(afterSourceRemoval.records == first.records)
    #expect(
      AchievementUnlockPersistence.decode(
        AchievementUnlockPersistence.encode(first.records)
      ) == first.records)
  }

  @Test("Every visible badge uses an available system symbol")
  func badgeSymbols() {
    let missing = UsageAnalytics(events: []).achievements
      .filter(\.isVisible)
      .filter {
        NSImage(systemSymbolName: $0.systemImage, accessibilityDescription: nil) == nil
      }
      .map(\.systemImage)

    #expect(missing.isEmpty, "Missing SF Symbols: \(missing)")
  }

  @Test("Tier collection headers use the requested rare-to-common icons")
  func tierCollectionIcons() {
    #expect(AchievementPresentation.collectionIcon(for: .diamond) == "💎")
    #expect(AchievementPresentation.collectionIcon(for: .gold) == "🏅")
    #expect(AchievementPresentation.collectionIcon(for: .silver) == "🥈")
    #expect(AchievementPresentation.collectionIcon(for: .bronze) == "🥉")
  }

  @Test("Compact badge cards use stable unlock status labels")
  func compactBadgeStatusLabels() {
    let achievements = UsageAnalytics(events: []).achievements
    let active = achievements.first { $0.availability == .active }!
    let comingSoon = achievements.first { $0.availability == .comingSoon }!

    #expect(
      AchievementPresentation.statusText(
        for: active,
        isUnlocked: false,
        language: .simplifiedChinese
      ) == "未解锁"
    )
    #expect(
      AchievementPresentation.statusText(
        for: active,
        isUnlocked: true,
        language: .simplifiedChinese
      ) == "已解锁"
    )
    #expect(
      AchievementPresentation.statusText(
        for: comingSoon,
        isUnlocked: false,
        language: .simplifiedChinese
      ) == "未开放"
    )
  }

  @Test("Locked badge artwork has a clearly subdued treatment")
  func lockedBadgeContrast() {
    #expect(AchievementPresentation.lockedArtworkOpacity <= 0.30)
    #expect(AchievementPresentation.lockedArtworkVeilOpacity >= 0.45)
  }

  @Test("New achievement presentation remains compact")
  func compactNewAchievementPresentation() {
    #expect(AchievementPresentation.popupWidth >= 280)
    #expect(AchievementPresentation.popupWidth <= 320)
    #expect(AchievementPresentation.popupCarouselHeight <= 240)
  }

  @Test("Achievement carousel starts on the first card and tracks page selection")
  func carouselSelection() {
    let achievements = Array(
      UsageAnalytics(events: []).achievements.filter(\.isVisible).prefix(3)
    )

    #expect(
      AchievementPresentation.initialCarouselPageID(in: achievements)
        == achievements.first?.id)
    #expect(
      AchievementPresentation.carouselPageIndex(
        in: achievements,
        selectedID: achievements[1].id
      ) == 1)
    #expect(
      AchievementPresentation.carouselPageIndex(
        in: achievements,
        selectedID: "missing"
      ) == nil)
    #expect(AchievementPresentation.initialCarouselPageID(in: []) == nil)
  }

  @Test("All sixty badges have unique bundled artwork")
  func badgeArtworkAssets() throws {
    let achievements = UsageAnalytics(events: []).achievements
    let fileNames = achievements.map(AchievementPresentation.artworkFileName(for:))
    let projectRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let artworkDirectory = projectRoot.appendingPathComponent(
      "Sources/UnsealedSpellbook/Resources/Badges")
    let missing = fileNames.filter {
      !FileManager.default.fileExists(
        atPath: artworkDirectory.appendingPathComponent($0).path)
    }

    #expect(achievements.count == 60)
    #expect(Set(fileNames).count == achievements.count)
    #expect(missing.isEmpty, "Missing badge artwork: \(missing)")
    let artwork = try fileNames.map {
      try Data(contentsOf: artworkDirectory.appendingPathComponent($0))
    }
    #expect(Set(artwork).count == achievements.count)
  }

}
