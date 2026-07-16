import AppKit
import ServiceManagement
import SwiftUI
import UnsealedSpellbookCore
import UnsealedSpellbookLanguage

struct SettingsPageView: View {
  let store: UsageStore
  let updateStore: GitHubReleaseStore
  @Environment(\.appLanguage) private var language

  @AppStorage(AppPreferences.providerKey(.claudeCode)) private var claudeEnabled = true
  @AppStorage(AppPreferences.providerKey(.codex)) private var codexEnabled = true
  @AppStorage(AppPreferences.providerKey(.geminiCLI)) private var geminiEnabled = true
  @AppStorage(AppPreferences.providerKey(.ohMyPi)) private var ohMyPiEnabled = true
  @AppStorage(AppPreferences.providerKey(.openCode)) private var openCodeEnabled = true
  @AppStorage(AppPreferences.refreshIntervalKey) private var refreshInterval = 300.0
  @AppStorage(AppPreferences.showMenuBarTotalKey) private var showMenuBarTotal = true
  @AppStorage(AppPreferences.automaticallyCheckForUpdatesKey) private
    var automaticallyCheckUpdates =
    true
  @AppStorage(AppPreferences.languageKey) private var languageCode =
    AppLanguage.simplifiedChinese.rawValue
  @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
  @State private var launchMessage: String?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: SpellbookDesign.spacing) {
        pageHeader

        HStack(alignment: .top, spacing: SpellbookDesign.spacing) {
          VStack(spacing: SpellbookDesign.spacing) {
            sourceSettings
            behaviorSettings
          }
          .frame(maxWidth: .infinity)

          VStack(spacing: SpellbookDesign.spacing) {
            privacySettings
            updateSettings
            diagnostics
          }
          .frame(maxWidth: .infinity)
        }
      }
      .padding(SpellbookDesign.spacing)
    }
    .background(SpellbookDesign.surfaceSoft)
    .onChange(of: claudeEnabled) { refreshAfterSettingsChange() }
    .onChange(of: codexEnabled) { refreshAfterSettingsChange() }
    .onChange(of: geminiEnabled) { refreshAfterSettingsChange() }
    .onChange(of: ohMyPiEnabled) { refreshAfterSettingsChange() }
    .onChange(of: openCodeEnabled) { refreshAfterSettingsChange() }
  }

  private var pageHeader: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(language.text(.settingsTitle))
        .font(.title2.weight(.semibold))
      Text(language.text(.settingsPrivacyDescription))
        .foregroundStyle(.secondary)
    }
    .padding(20)
    .frame(maxWidth: .infinity, alignment: .leading)
    .spellbookPanel()
  }

  private var sourceSettings: some View {
    settingsCard(language.text(.settingsDataSources), systemImage: "externaldrive") {
      providerToggle(.claudeCode, isOn: $claudeEnabled)
      providerToggle(.codex, isOn: $codexEnabled)
      providerToggle(.geminiCLI, isOn: $geminiEnabled)
      providerToggle(.ohMyPi, isOn: $ohMyPiEnabled)
      providerToggle(.openCode, isOn: $openCodeEnabled)
    }
  }

  private var behaviorSettings: some View {
    settingsCard(language.text(.settingsResidentBehavior), systemImage: "menubar.rectangle") {
      HStack {
        Text(language.text(.settingsLanguage))
        Spacer()
        Picker(language.text(.settingsLanguage), selection: $languageCode) {
          ForEach(AppLanguage.allCases) { option in
            Text(option.nativeName).tag(option.rawValue)
          }
        }
        .labelsHidden()
        .frame(width: 140)
      }

      Text(language.text(.settingsLanguageDescription))
        .font(.caption)
        .foregroundStyle(.secondary)

      Toggle(language.text(.settingsShowMenuBarTotal), isOn: $showMenuBarTotal)
      Toggle(
        language.text(.settingsLaunchAtLogin),
        isOn: Binding(
          get: { launchAtLogin },
          set: { enabled in updateLaunchAtLogin(enabled) }
        )
      )

      HStack {
        Text(language.text(.settingsRefreshInterval))
        Spacer()
        Picker(language.text(.settingsRefreshInterval), selection: $refreshInterval) {
          Text(language.text(.settingsOneMinute)).tag(60.0)
          Text(language.text(.settingsFiveMinutes)).tag(300.0)
          Text(language.text(.settingsFifteenMinutes)).tag(900.0)
        }
        .labelsHidden()
        .frame(width: 120)
      }

      if let launchMessage {
        Label(launchMessage, systemImage: "exclamationmark.triangle")
          .font(.caption)
          .foregroundStyle(.orange)
      }
    }
  }

  private var privacySettings: some View {
    settingsCard(language.text(.settingsLocalData), systemImage: "lock.shield") {
      sourcePath("Claude Code", LocalUsageLocations.standard.claudeCodeDirectory)
      sourcePath("Codex", LocalUsageLocations.standard.codexDirectory)
      ForEach(
        Array(LocalUsageLocations.standard.geminiCLIDirectories.enumerated()),
        id: \.offset
      ) { index, directory in
        sourcePath(index == 0 ? "Gemini CLI" : "Gemini CLI Legacy", directory)
      }
      sourcePath("OpenCode", LocalUsageLocations.standard.openCodeDatabase)
      if let directory = LocalUsageLocations.standard.ohMyPiDirectory {
        sourcePath("Oh My Pi", directory)
      }
    }
  }

  private var updateSettings: some View {
    settingsCard(language.text(.settingsUpdates), systemImage: "arrow.triangle.2.circlepath") {
      Toggle(
        language.text(.settingsAutomaticallyCheckUpdates),
        isOn: $automaticallyCheckUpdates
      )

      HStack {
        Text(
          language.text(
            .settingsCurrentVersionFormat,
            updateStore.currentVersion
          )
        )
        Spacer()
        Button {
          AppPreferences.recordUpdateCheck()
          Task { await updateStore.check() }
        } label: {
          if updateStore.state == .checking {
            HStack(spacing: 6) {
              ProgressView().controlSize(.small)
              Text(language.text(.settingsCheckingUpdates))
            }
          } else {
            Text(language.text(.settingsCheckUpdates))
          }
        }
        .disabled(updateStore.state == .checking)
      }

      updateStatus

      Text(language.text(.settingsManualUpdateDescription))
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  @ViewBuilder
  private var updateStatus: some View {
    switch updateStore.state {
    case .idle, .checking:
      EmptyView()
    case .upToDate(let latestTag):
      Label(
        language.text(.settingsUpToDateFormat, latestTag),
        systemImage: "checkmark.circle.fill"
      )
      .foregroundStyle(SpellbookDesign.success)
    case .updateAvailable(let latestTag):
      HStack {
        Label(
          language.text(.settingsUpdateAvailableFormat, latestTag),
          systemImage: "arrow.down.circle.fill"
        )
        .foregroundStyle(SpellbookDesign.accent)
        Spacer()
        Button(language.text(.settingsOpenRelease)) {
          NSWorkspace.shared.open(updateStore.releasePageURL)
        }
      }
    case .failed:
      Label(
        language.text(.settingsUpdateCheckFailed),
        systemImage: "exclamationmark.triangle"
      )
      .foregroundStyle(.orange)
    }
  }

  private var diagnostics: some View {
    settingsCard(language.text(.settingsStatus), systemImage: "waveform.path.ecg") {
      HStack {
        if let updated = store.lastUpdated {
          Text(
            language.text(
              .settingsUpdatedAtFormat,
              updated.formatted(
                .dateTime.hour().minute().second().locale(language.locale)
              )
            )
          )
        } else {
          Text(language.text(.settingsNotScanned))
        }
        Spacer()
        Button(language.text(.settingsRefreshNow)) { Task { await store.refresh() } }
          .disabled(store.isRefreshing)
      }

      if let diagnostics = store.diagnostics {
        Text(
          language.text(
            .settingsDiagnosticsFormat,
            diagnostics.filesRead,
            diagnostics.bytesRead.formatted(
              .byteCount(style: .file).locale(language.locale)
            ),
            diagnostics.sourceErrors
          )
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      HStack {
        Spacer()
        Button(language.text(.settingsQuit)) {
          NSApplication.shared.terminate(nil)
        }
      }
    }
  }

  private func providerToggle(_ provider: AIProvider, isOn: Binding<Bool>) -> some View {
    Toggle(isOn: isOn) {
      Label(provider.displayName, systemImage: provider.systemImage)
        .foregroundStyle(provider.tintColor)
    }
    .tint(provider.tintColor)
  }

  private func sourcePath(_ name: String, _ url: URL) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(name).font(.subheadline.weight(.medium))
      Text(abbreviatedPath(url))
        .font(.caption.monospaced())
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
    }
  }

  private func settingsCard<Content: View>(
    _ title: String,
    systemImage: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Label(title, systemImage: systemImage)
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(SpellbookDesign.accent)
      Divider().overlay(SpellbookDesign.line)
      content()
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .spellbookPanel()
  }

  private func refreshAfterSettingsChange() {
    Task { await store.refresh() }
  }

  private func updateLaunchAtLogin(_ enabled: Bool) {
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
      launchAtLogin = SMAppService.mainApp.status == .enabled
      launchMessage =
        SMAppService.mainApp.status == .requiresApproval
        ? language.text(.settingsLaunchApprovalRequired)
        : nil
    } catch {
      launchAtLogin = SMAppService.mainApp.status == .enabled
      launchMessage = language.text(
        .settingsLaunchUpdateFailedFormat,
        error.localizedDescription
      )
    }
  }

  private func abbreviatedPath(_ url: URL) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    return url.path.replacingOccurrences(of: home, with: "~")
  }
}
