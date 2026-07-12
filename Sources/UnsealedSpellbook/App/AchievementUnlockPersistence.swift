import Foundation
import UnsealedSpellbookCore

struct AchievementUnlockRecord: Codable, Equatable, Sendable {
  let id: String
  let criteriaVersion: Int
  let unlockedAt: Date
  let unlockValue: String
}

enum AchievementUnlockPersistence {
  struct MergeResult {
    let records: [AchievementUnlockRecord]
    let newlyUnlocked: [Achievement]
  }

  static func merge(
    records: [AchievementUnlockRecord],
    achievements: [Achievement],
    now: Date = Date()
  ) -> MergeResult {
    let knownIDs = Set(records.map(\.id))
    let newlyUnlocked = achievements.filter {
      $0.isUnlocked && !knownIDs.contains($0.id)
    }
    let additions = newlyUnlocked.map {
      AchievementUnlockRecord(
        id: $0.id,
        criteriaVersion: $0.criteriaVersion,
        unlockedAt: now,
        unlockValue: $0.progressLabel
      )
    }

    return MergeResult(
      records: (records + additions).sorted { $0.id < $1.id },
      newlyUnlocked: newlyUnlocked
    )
  }

  static func encode(_ records: [AchievementUnlockRecord]) -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return (try? encoder.encode(records)) ?? Data()
  }

  static func decode(_ data: Data) -> [AchievementUnlockRecord] {
    (try? JSONDecoder().decode([AchievementUnlockRecord].self, from: data)) ?? []
  }
}
