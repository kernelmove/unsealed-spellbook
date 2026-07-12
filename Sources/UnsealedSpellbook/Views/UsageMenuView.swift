import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class DashboardNavigation {
  var selectedPage = DashboardPage.details
}

struct UsageMenuView: View {
  let store: UsageStore
  @Bindable var navigation: DashboardNavigation
  @Environment(\.colorScheme) private var colorScheme
  @State private var preferredColorScheme: ColorScheme?

  var body: some View {
    VStack(spacing: 0) {
      navigationBar
      Divider()
      pageContent
    }
    .frame(width: SpellbookDesign.windowSize.width, height: SpellbookDesign.windowSize.height)
    .background(SpellbookDesign.background)
    .tint(SpellbookDesign.accent)
    .preferredColorScheme(preferredColorScheme)
  }

  private var navigationBar: some View {
    ZStack {
      SpellbookSegmentedControl(
        options: DashboardPage.allCases,
        selection: $navigation.selectedPage
      ) { $0.title }
      .font(.subheadline)
      .frame(width: 250)
      .accessibilityLabel("页面")

      HStack(spacing: 0) {
        HStack(spacing: 8) {
          Image(systemName: "sparkles")
            .font(.system(size: 15, weight: .semibold))
          Text("Unsealed Spellbook")
            .font(.system(size: 16, weight: .semibold, design: .serif))
            .tracking(-0.32)
        }
        .foregroundStyle(SpellbookDesign.accent)

        Spacer(minLength: 0)

        HStack(spacing: 2) {
          Button {
            Task { await store.refresh() }
          } label: {
            if store.isRefreshing {
              ProgressView().controlSize(.small)
            } else {
              Image(systemName: "arrow.clockwise")
            }
          }
          .disabled(store.isRefreshing)
          .frame(width: 30, height: 30)
          .help("刷新本地用量")
          .accessibilityLabel("刷新本地用量")

          Button {
            preferredColorScheme = effectiveColorScheme == .dark ? .light : .dark
          } label: {
            Image(systemName: effectiveColorScheme == .dark ? "sun.max" : "moon")
          }
          .frame(width: 30, height: 30)
          .help(effectiveColorScheme == .dark ? "切换到浅色模式" : "切换到深色模式")
          .accessibilityLabel(
            effectiveColorScheme == .dark ? "切换到浅色模式" : "切换到深色模式"
          )

          Button {
            NSApplication.shared.terminate(nil)
          } label: {
            Image(systemName: "power")
          }
          .frame(width: 30, height: 30)
          .help("退出 Unsealed Spellbook")
          .accessibilityLabel("退出 Unsealed Spellbook")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .font(.system(size: 15))
        .controlSize(.small)
      }
      .padding(.horizontal, 18)
    }
    .frame(height: SpellbookDesign.toolbarHeight)
    .background(SpellbookDesign.toolbar)
  }

  private var effectiveColorScheme: ColorScheme {
    preferredColorScheme ?? colorScheme
  }

  @ViewBuilder
  private var pageContent: some View {
    switch navigation.selectedPage {
    case .settings:
      SettingsPageView(store: store)
    case .details:
      if let analytics = store.analytics {
        DetailDashboardView(analytics: analytics)
      } else {
        loadingView
      }
    case .achievements:
      if let analytics = store.analytics {
        AchievementsView(analytics: analytics)
      } else {
        loadingView
      }
    }
  }

  private var loadingView: some View {
    ContentUnavailableView {
      Label("正在读取本地日志", systemImage: "wand.and.stars")
    } description: {
      Text("首次扫描完成后会在内存中增量更新。")
    } actions: {
      ProgressView().controlSize(.small)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

enum DashboardPage: String, CaseIterable, Identifiable {
  case details
  case achievements
  case settings

  var id: Self { self }

  var title: String {
    switch self {
    case .details: "概览"
    case .achievements: "徽章"
    case .settings: "设置"
    }
  }
}
