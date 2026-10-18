import AppKit
import Observation
import SwiftUI
import UnsealedSpellbookLanguage

@MainActor
@Observable
final class DashboardNavigation {
  var selectedPage = DashboardPage.details
}

struct UsageMenuView: View {
  let store: UsageStore
  let updateStore: GitHubReleaseStore
  @Bindable var navigation: DashboardNavigation
  @Environment(\.appLanguage) private var language
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.colorScheme) private var colorScheme
  @State private var preferredColorScheme: ColorScheme?

  var body: some View {
    VStack(spacing: 0) {
      navigationBar
      pageContent
        .id(navigation.selectedPage)
        .transition(
          reduceMotion
            ? .opacity
            : .opacity.combined(with: .scale(scale: 0.99, anchor: .top))
        )
    }
    .animation(
      reduceMotion
        ? .easeOut(duration: 0.12)
        : .spring(response: 0.34, dampingFraction: 1),
      value: navigation.selectedPage
    )
    .frame(
      minWidth: SpellbookDesign.minimumWindowSize.width,
      idealWidth: SpellbookDesign.windowSize.width,
      maxWidth: .infinity,
      minHeight: SpellbookDesign.minimumWindowSize.height,
      idealHeight: SpellbookDesign.windowSize.height,
      maxHeight: .infinity
    )
    .background(SpellbookDesign.background)
    .tint(SpellbookDesign.accent)
    .preferredColorScheme(preferredColorScheme)
  }

  private var navigationBar: some View {
    ZStack {
      SpellbookSegmentedControl(
        options: DashboardPage.allCases,
        selection: $navigation.selectedPage
      ) { $0.title(language: language) }
      .font(.subheadline)
      .frame(width: 250)
      .accessibilityLabel(language.text(.accessibilityPage))

      HStack(spacing: 0) {
        HStack(spacing: 8) {
          Image(systemName: "sparkles")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(SpellbookDesign.accent)
          Text("Unsealed Spellbook")
            .font(.system(size: 16, weight: .semibold, design: .serif))
            .tracking(-0.32)
            .foregroundStyle(.primary)
        }

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
          .help(language.text(.actionRefreshUsage))
          .accessibilityLabel(language.text(.actionRefreshUsage))

          Button {
            preferredColorScheme = effectiveColorScheme == .dark ? .light : .dark
          } label: {
            Image(systemName: effectiveColorScheme == .dark ? "sun.max" : "moon")
          }
          .frame(width: 30, height: 30)
          .help(themeActionTitle)
          .accessibilityLabel(
            themeActionTitle
          )

          Button {
            NSApplication.shared.terminate(nil)
          } label: {
            Image(systemName: "power")
          }
          .frame(width: 30, height: 30)
          .help(language.text(.actionQuit))
          .accessibilityLabel(language.text(.actionQuit))
        }
        .buttonStyle(SpellbookPressButtonStyle())
        .foregroundStyle(.secondary)
        .font(.system(size: 15))
        .controlSize(.small)
      }
      .padding(.horizontal, 18)
    }
    .frame(height: SpellbookDesign.toolbarHeight)
    .background(SpellbookDesign.surface)
    .overlay(alignment: .bottom) {
      Divider().overlay(SpellbookDesign.line)
    }
    .zIndex(1)
  }

  private var effectiveColorScheme: ColorScheme {
    preferredColorScheme ?? colorScheme
  }

  private var themeActionTitle: String {
    language.text(
      effectiveColorScheme == .dark ? .actionSwitchToLightMode : .actionSwitchToDarkMode
    )
  }

  @ViewBuilder
  private var pageContent: some View {
    switch navigation.selectedPage {
    case .settings:
      SettingsPageView(store: store, updateStore: updateStore)
    case .details:
      if let analytics = store.analytics {
        DetailDashboardView(
          analytics: analytics,
          pricingCatalog: store.pricingCatalog,
          enabledProviders: AppPreferences.enabledProviders()
        )
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
      Label(language.text(.loadingLocalLogs), systemImage: "wand.and.stars")
    } description: {
      Text(language.text(.loadingDescription))
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

  func title(language: AppLanguage) -> String {
    switch self {
    case .details: language.text(.navigationOverview)
    case .achievements: language.text(.navigationAchievements)
    case .settings: language.text(.navigationSettings)
    }
  }
}
