import AppKit
import SwiftUI
import UnsealedSpellbookCore

enum AchievementPresentation {
  static let tierOrder: [BadgeTier] = [.diamond, .gold, .silver, .bronze]
  static let popupWidth: CGFloat = 304
  static let popupCarouselHeight: CGFloat = 220
  static let lockedArtworkOpacity = 0.28
  static let lockedArtworkVeilOpacity = 0.52

  static func collectionIcon(for tier: BadgeTier) -> String {
    switch tier {
    case .diamond: "💎"
    case .gold: "🏅"
    case .silver: "🥈"
    case .bronze: "🥉"
    }
  }

  static func artworkFileName(for achievement: Achievement) -> String {
    "\(achievement.id).png"
  }

  static func initialCarouselPageID(in achievements: [Achievement]) -> String? {
    achievements.first?.id
  }

  static func carouselPageIndex(
    in achievements: [Achievement],
    selectedID: String?
  ) -> Int? {
    achievements.firstIndex { $0.id == selectedID }
  }

  static func statusText(for achievement: Achievement, isUnlocked: Bool) -> String {
    if achievement.availability == .comingSoon { return "未开放" }
    return isUnlocked ? "已解锁" : "未解锁"
  }

  static func statusSystemImage(for achievement: Achievement, isUnlocked: Bool) -> String {
    if achievement.availability == .comingSoon { return "clock.fill" }
    return isUnlocked ? "checkmark.seal.fill" : "lock.fill"
  }

  static func unseen(
    in achievements: [Achievement],
    acknowledgedIDs: Set<String>
  ) -> [Achievement] {
    unseen(
      in: achievements,
      unlockedIDs: Set(achievements.filter(\.isUnlocked).map(\.id)),
      acknowledgedIDs: acknowledgedIDs
    )
  }

  static func unseen(
    in achievements: [Achievement],
    unlockedIDs: Set<String>,
    acknowledgedIDs: Set<String>
  ) -> [Achievement] {
    achievements
      .filter {
        $0.isVisible
          && unlockedIDs.contains($0.id)
          && !acknowledgedIDs.contains($0.id)
      }
      .sorted {
        let left = tierOrder.firstIndex(of: $0.tier) ?? tierOrder.count
        let right = tierOrder.firstIndex(of: $1.tier) ?? tierOrder.count
        return left == right ? $0.title < $1.title : left < right
      }
  }
}

struct AchievementsView: View {
  let analytics: UsageAnalytics

  @AppStorage(AppPreferences.acknowledgedAchievementsKey)
  private var acknowledgedAchievementIDs = ""
  @AppStorage(AppPreferences.achievementUnlockRecordsKey)
  private var unlockRecordsData = Data()
  @State private var newAchievements: [Achievement] = []
  @State private var unlockRecordsByID: [String: AchievementUnlockRecord] = [:]
  @State private var expandedTierIDs = Set(AchievementPresentation.tierOrder.map(\.rawValue))

  private let summaryColumns = [
    GridItem(.flexible(), spacing: 10),
    GridItem(.flexible(), spacing: 10),
    GridItem(.flexible(), spacing: 10),
    GridItem(.flexible(), spacing: 10),
  ]
  var body: some View {
    let overview = analytics.overview
    let allAchievements = analytics.achievements
    let achievements = allAchievements.filter(\.isVisible)
    let unlockSignature = allAchievements.filter(\.isUnlocked).map(\.id).joined(separator: "|")

    let unlockedIDs = Set(achievements.filter(isEffectivelyUnlocked).map(\.id))

    ZStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
              Text("徽章与总览")
                .font(.title2.weight(.semibold))
              Text("从稀有到普通，点亮你的 AI 工具旅程")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: summaryColumns, spacing: 10) {
              SummaryMetric(
                title: "累计 Token",
                value: overview.totalTokens.formatted(.number.notation(.compactName)),
                accessibilityValue: overview.totalTokens.formatted(),
                systemImage: "sum",
                color: SpellbookDesign.accent
              )
              SummaryMetric(
                title: "活跃天数",
                value: "\(overview.activeDays)",
                accessibilityValue: "\(overview.activeDays) 天",
                systemImage: "calendar",
                color: SpellbookDesign.metricBlue
              )
              SummaryMetric(
                title: "当前连击",
                value: "\(overview.currentStreak) 天",
                accessibilityValue: "\(overview.currentStreak) 天",
                systemImage: "flame.fill",
                color: SpellbookDesign.metricPurple
              )
              SummaryMetric(
                title: "缓存命中",
                value: overview.cacheHitRate.formatted(.percent.precision(.fractionLength(0))),
                accessibilityValue: overview.cacheHitRate.formatted(
                  .percent.precision(.fractionLength(0))
                ),
                systemImage: "bolt.fill",
                color: SpellbookDesign.success
              )
            }
          }
          .padding(20)
          .spellbookPanel()

          HStack(alignment: .firstTextBaseline) {
            Text("徽章收藏")
              .font(.headline)
            Spacer()
            Text("已点亮 \(achievements.filter(isEffectivelyUnlocked).count) / \(achievements.count)")
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          ForEach(AchievementPresentation.tierOrder, id: \.rawValue) { tier in
            let tierAchievements = achievements.filter { $0.tier == tier }
            TierAchievementCollection(
              tier: tier,
              achievements: tierAchievements,
              unlockedIDs: unlockedIDs,
              unlockRecordsByID: unlockRecordsByID,
              isExpanded: expansionBinding(for: tier)
            )
          }
        }
        .padding(SpellbookDesign.spacing)
        .frame(maxWidth: .infinity, alignment: .leading)
      }

      if !newAchievements.isEmpty {
        Color.black.opacity(0.48)
          .ignoresSafeArea()
          .transition(.opacity)
          .accessibilityHidden(true)

        NewAchievementModal(achievements: newAchievements) {
          withAnimation(.easeOut(duration: 0.2)) {
            newAchievements.removeAll()
          }
        }
        .transition(.scale(scale: 0.96).combined(with: .opacity))
      }
    }
    .background(SpellbookDesign.surfaceSoft)
    .onAppear { updateUnlocks(from: allAchievements) }
    .onChange(of: unlockSignature) {
      updateUnlocks(from: allAchievements)
    }
  }

  private func isEffectivelyUnlocked(_ achievement: Achievement) -> Bool {
    achievement.isUnlocked || unlockRecordsByID[achievement.id] != nil
  }

  private func expansionBinding(for tier: BadgeTier) -> Binding<Bool> {
    Binding(
      get: { expandedTierIDs.contains(tier.rawValue) },
      set: { isExpanded in
        if isExpanded {
          expandedTierIDs.insert(tier.rawValue)
        } else {
          expandedTierIDs.remove(tier.rawValue)
        }
      }
    )
  }

  private func updateUnlocks(from achievements: [Achievement]) {
    let existingRecords = AchievementUnlockPersistence.decode(unlockRecordsData)
    let merged = AchievementUnlockPersistence.merge(
      records: existingRecords,
      achievements: achievements
    )
    let unlockedIDs = Set(merged.records.map(\.id))

    unlockRecordsByID = merged.records.reduce(into: [:]) { records, record in
      records[record.id] = record
    }
    if merged.records != existingRecords {
      unlockRecordsData = AchievementUnlockPersistence.encode(merged.records)
    }
    presentNewAchievements(from: achievements, unlockedIDs: unlockedIDs)
  }

  private func presentNewAchievements(
    from achievements: [Achievement],
    unlockedIDs: Set<String>
  ) {
    let acknowledged = Set(
      acknowledgedAchievementIDs.split(separator: ",").map(String.init)
    )
    let unseen = AchievementPresentation.unseen(
      in: achievements,
      unlockedIDs: unlockedIDs,
      acknowledgedIDs: acknowledged
    )
    guard !unseen.isEmpty else { return }

    withAnimation(.easeOut(duration: 0.2)) {
      newAchievements = unseen
    }
    acknowledgedAchievementIDs =
      acknowledged
      .union(unseen.map(\.id))
      .sorted()
      .joined(separator: ",")
  }
}

private struct TierAchievementCollection: View {
  let tier: BadgeTier
  let achievements: [Achievement]
  let unlockedIDs: Set<String>
  let unlockRecordsByID: [String: AchievementUnlockRecord]
  @Binding var isExpanded: Bool

  private let columns = [GridItem(.adaptive(minimum: 170), spacing: 12)]

  var body: some View {
    VStack(spacing: 0) {
      Button {
        withAnimation(.easeInOut(duration: 0.18)) {
          isExpanded.toggle()
        }
      } label: {
        HStack(spacing: 10) {
          Text(AchievementPresentation.collectionIcon(for: tier))
            .font(.title3)
            .accessibilityHidden(true)

          VStack(alignment: .leading, spacing: 2) {
            Text("\(tier.displayName)级收藏")
              .font(.subheadline.weight(.semibold))
            Text(
              "\(achievements.filter { unlockedIDs.contains($0.id) }.count) / \(achievements.count) 已点亮"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
          }

          Spacer()

          Image(systemName: "chevron.down")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .rotationEffect(.degrees(isExpanded ? 0 : -90))
            .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .padding(14)
      .accessibilityLabel("\(tier.displayName)级收藏")
      .accessibilityValue(isExpanded ? "已展开" : "已折叠")
      .accessibilityHint(isExpanded ? "折叠徽章列表" : "展开徽章列表")

      if isExpanded {
        Divider()

        LazyVGrid(columns: columns, spacing: 12) {
          ForEach(achievements) { achievement in
            AchievementCard(
              achievement: achievement,
              isUnlocked: unlockedIDs.contains(achievement.id),
              unlockRecord: unlockRecordsByID[achievement.id]
            )
          }
        }
        .padding(12)
        .transition(.opacity)
      }
    }
    .spellbookPanel()
  }
}

private struct SummaryMetric: View {
  let title: String
  let value: String
  let accessibilityValue: String
  let systemImage: String
  let color: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      Label(title, systemImage: systemImage)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
      Text(value)
        .font(.system(size: 23, weight: .semibold).monospacedDigit())
        .foregroundStyle(color)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
    .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
    .padding(14)
    .background(
      SpellbookDesign.surface,
      in: RoundedRectangle(cornerRadius: 12, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .stroke(SpellbookDesign.line, lineWidth: 1)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(title)
    .accessibilityValue(accessibilityValue)
  }
}

private struct AchievementCard: View {
  let achievement: Achievement
  let isUnlocked: Bool
  let unlockRecord: AchievementUnlockRecord?
  @State private var isShowingDetails = false

  private var displayColor: Color {
    isUnlocked ? achievement.tier.tintColor : SpellbookDesign.muted
  }

  private var statusText: String {
    AchievementPresentation.statusText(for: achievement, isUnlocked: isUnlocked)
  }

  var body: some View {
    Button {
      isShowingDetails = true
    } label: {
      VStack(spacing: 10) {
        AchievementArtwork(
          achievement: achievement,
          isUnlocked: isUnlocked,
          size: 76
        )
        .accessibilityHidden(true)

        Text(achievement.title)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.primary)
          .multilineTextAlignment(.center)
          .lineLimit(1)
          .minimumScaleFactor(0.8)

        Label(
          statusText,
          systemImage: AchievementPresentation.statusSystemImage(
            for: achievement,
            isUnlocked: isUnlocked
          )
        )
        .font(.caption.weight(.medium))
        .foregroundStyle(displayColor)
      }
      .padding(14)
      .frame(maxWidth: .infinity, minHeight: 152, alignment: .center)
      .background(SpellbookDesign.surface, in: RoundedRectangle(cornerRadius: 14))
      .overlay {
        RoundedRectangle(cornerRadius: 14)
          .stroke(SpellbookDesign.line, lineWidth: 1)
      }
      .contentShape(RoundedRectangle(cornerRadius: 14))
    }
    .buttonStyle(.plain)
    .help("查看 \(achievement.title) 详情")
    .popover(isPresented: $isShowingDetails) {
      AchievementDetailPopover(
        achievement: achievement,
        isUnlocked: isUnlocked,
        unlockRecord: unlockRecord
      )
    }
    .accessibilityLabel(achievement.title)
    .accessibilityValue(statusText)
    .accessibilityHint("打开徽章详情")
  }
}

struct AchievementDetailPopover: View {
  let achievement: Achievement
  let isUnlocked: Bool
  let unlockRecord: AchievementUnlockRecord?

  private var statusText: String {
    AchievementPresentation.statusText(for: achievement, isUnlocked: isUnlocked)
  }

  private var progressValue: Double {
    isUnlocked ? 1 : achievement.progress
  }

  private var progressText: String {
    if achievement.availability == .comingSoon { return "尚未开放" }
    if isUnlocked { return unlockRecord?.unlockValue ?? "已完成" }
    return achievement.progressLabel
  }

  private var unlockDateText: String {
    guard let unlockedAt = unlockRecord?.unlockedAt else {
      return isUnlocked ? "暂无记录" : "尚未解锁"
    }
    return unlockedAt.formatted(date: .long, time: .omitted)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .top, spacing: 16) {
        VStack(spacing: 6) {
          AchievementArtwork(
            achievement: achievement,
            isUnlocked: true,
            size: 96
          )
          Text("解锁后预览")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)

        VStack(alignment: .leading, spacing: 7) {
          Text(achievement.title)
            .font(.title3.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)

          Text("\(achievement.tier.displayName)级徽章")
            .font(.caption.weight(.semibold))
            .foregroundStyle(achievement.tier.tintColor)

          Label(
            statusText,
            systemImage: AchievementPresentation.statusSystemImage(
              for: achievement,
              isUnlocked: isUnlocked
            )
          )
          .font(.caption)
          .foregroundStyle(isUnlocked ? achievement.tier.tintColor : SpellbookDesign.muted)
        }

        Spacer(minLength: 0)
      }

      Divider()

      VStack(alignment: .leading, spacing: 7) {
        HStack {
          Text("进度")
            .font(.subheadline.weight(.semibold))
          Spacer()
          Text(progressText)
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }

        ProgressView(value: progressValue)
          .progressViewStyle(.linear)
          .tint(isUnlocked ? achievement.tier.tintColor : SpellbookDesign.muted)
          .accessibilityLabel("解锁进度")
          .accessibilityValue(progressText)
      }

      VStack(alignment: .leading, spacing: 5) {
        Text("说明")
          .font(.subheadline.weight(.semibold))
        Text(achievement.detail)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      HStack(alignment: .firstTextBaseline) {
        Text("解锁日期")
          .font(.subheadline.weight(.semibold))
        Spacer()
        Text(unlockDateText)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
    }
    .padding(18)
    .frame(width: 350)
  }
}

struct AchievementArtwork: View {
  let achievement: Achievement
  let isUnlocked: Bool
  let size: CGFloat

  var body: some View {
    Group {
      if let image = BadgeArtworkStore.image(for: achievement) {
        Image(nsImage: image)
          .resizable()
          .interpolation(.high)
      } else {
        ZStack {
          RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
            .fill(achievement.tier.tintColor.opacity(0.14))
          Image(systemName: achievement.systemImage)
            .font(.system(size: size * 0.34, weight: .semibold))
            .foregroundStyle(achievement.tier.tintColor)
        }
      }
    }
    .aspectRatio(1, contentMode: .fit)
    .frame(width: size, height: size)
    .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    .saturation(isUnlocked ? 1 : 0)
    .opacity(isUnlocked ? 1 : AchievementPresentation.lockedArtworkOpacity)
    .overlay {
      if !isUnlocked {
        ZStack {
          RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
            .fill(SpellbookDesign.surface.opacity(AchievementPresentation.lockedArtworkVeilOpacity))

          Image(systemName: "lock.fill")
            .font(.system(size: max(11, size * 0.16), weight: .semibold))
            .foregroundStyle(SpellbookDesign.muted)
            .padding(size * 0.08)
            .background(SpellbookDesign.surface.opacity(0.92), in: Circle())
        }
      }
    }
    .overlay {
      RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
        .stroke(isUnlocked ? achievement.tier.tintColor.opacity(0.24) : SpellbookDesign.line)
    }
  }
}

@MainActor
private enum BadgeArtworkStore {
  static let cache: NSCache<NSString, NSImage> = {
    let cache = NSCache<NSString, NSImage>()
    cache.totalCostLimit = 8 * 1_024 * 1_024
    return cache
  }()

  static func image(for achievement: Achievement) -> NSImage? {
    let key = achievement.id as NSString
    if let cached = cache.object(forKey: key) { return cached }

    let fileName = AchievementPresentation.artworkFileName(for: achievement)
    for bundle in [Bundle.main, Bundle.module] {
      guard
        let url = bundle.url(
          forResource: fileName,
          withExtension: nil,
          subdirectory: "Badges"
        ),
        let image = NSImage(contentsOf: url)
      else { continue }

      cache.setObject(
        image,
        forKey: key,
        cost: Int(image.size.width * image.size.height * 4)
      )
      return image
    }
    return nil
  }
}

struct NewAchievementModal: View {
  let achievements: [Achievement]
  let dismiss: () -> Void
  @State private var selectedAchievementID: String?

  init(achievements: [Achievement], dismiss: @escaping () -> Void) {
    self.achievements = achievements
    self.dismiss = dismiss
    _selectedAchievementID = State(
      initialValue: AchievementPresentation.initialCarouselPageID(in: achievements)
    )
  }

  var body: some View {
    VStack(spacing: 10) {
      VStack(spacing: 12) {
        Label("新徽章已点亮", systemImage: "sparkles")
          .font(.headline)
          .foregroundStyle(SpellbookDesign.accent)

        ScrollView(.horizontal) {
          LazyHStack(spacing: 0) {
            ForEach(achievements) { achievement in
              VStack(spacing: 8) {
                AchievementArtwork(
                  achievement: achievement,
                  isUnlocked: true,
                  size: 112
                )

                Text(achievement.title)
                  .font(.title3.weight(.semibold))
                  .lineLimit(1)

                Text("\(achievement.tier.displayName)级徽章")
                  .font(.caption.weight(.semibold))
                  .foregroundStyle(achievement.tier.tintColor)

                Text(achievement.detail)
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .multilineTextAlignment(.center)
                  .lineLimit(2)
                  .frame(minHeight: 32, alignment: .top)
              }
              .frame(width: AchievementPresentation.popupWidth - 32)
              .id(achievement.id)
            }
          }
          .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $selectedAchievementID)
        .frame(
          width: AchievementPresentation.popupWidth - 32,
          height: AchievementPresentation.popupCarouselHeight
        )
        .accessibilityLabel("新徽章轮播")
        .accessibilityValue(carouselAccessibilityValue)

        Button(action: dismiss) {
          Text("收下徽章")
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(SpellbookDesign.accent, in: Capsule())
        .accessibilityLabel("收下新徽章")
      }
      .padding(16)
      .frame(width: AchievementPresentation.popupWidth)
      .background(SpellbookDesign.surface, in: RoundedRectangle(cornerRadius: 18))
      .overlay {
        RoundedRectangle(cornerRadius: 18).stroke(SpellbookDesign.line)
      }
      .shadow(color: .black.opacity(0.24), radius: 24, y: 12)

      if achievements.count > 1 {
        AchievementPageDots(
          achievements: achievements,
          selection: $selectedAchievementID
        )
      }

      Button(action: dismiss) {
        Image(systemName: "xmark")
          .font(.system(size: 14, weight: .bold))
          .frame(width: 34, height: 34)
          .contentShape(Circle())
      }
      .buttonStyle(.plain)
      .foregroundStyle(.white)
      .background(Color.black.opacity(0.28), in: Circle())
      .overlay { Circle().stroke(Color.white.opacity(0.9), lineWidth: 1.5) }
      .accessibilityLabel("关闭新徽章提示")
    }
    .accessibilityElement(children: .contain)
  }

  private var carouselAccessibilityValue: String {
    guard
      let index = AchievementPresentation.carouselPageIndex(
        in: achievements,
        selectedID: selectedAchievementID
      )
    else { return "共 \(achievements.count) 枚" }
    return "第 \(index + 1) 枚，共 \(achievements.count) 枚"
  }
}

private struct AchievementPageDots: View {
  let achievements: [Achievement]
  @Binding var selection: String?

  var body: some View {
    HStack(spacing: 2) {
      ForEach(achievements.indices, id: \.self) { index in
        let achievement = achievements[index]
        let isSelected = selection == achievement.id

        Button {
          withAnimation(.easeInOut(duration: 0.2)) {
            selection = achievement.id
          }
        } label: {
          Circle()
            .fill(isSelected ? Color.white : Color.clear)
            .overlay {
              Circle().stroke(Color.white.opacity(isSelected ? 1 : 0.72), lineWidth: 1)
            }
            .frame(width: 7, height: 7)
            .frame(width: 18, height: 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(achievement.title)，第 \(index + 1) 页")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
      }
    }
  }
}
