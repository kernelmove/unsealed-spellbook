import SwiftUI
import UnsealedSpellbookLanguage

private struct AppLanguageEnvironmentKey: EnvironmentKey {
  static let defaultValue = AppLanguage.simplifiedChinese
}

extension EnvironmentValues {
  var appLanguage: AppLanguage {
    get { self[AppLanguageEnvironmentKey.self] }
    set { self[AppLanguageEnvironmentKey.self] = newValue }
  }
}

struct LanguageRoot<Content: View>: View {
  @AppStorage(AppPreferences.languageKey) private var languageCode =
    AppLanguage.simplifiedChinese.rawValue

  let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  private var language: AppLanguage {
    AppLanguage(rawValue: languageCode) ?? .simplifiedChinese
  }

  var body: some View {
    content
      .environment(\.appLanguage, language)
      .environment(\.locale, language.locale)
  }
}
