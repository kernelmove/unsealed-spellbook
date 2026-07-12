import AppKit
import ServiceManagement
import SwiftUI
import UnsealedSpellbookCore

struct SettingsPageView: View {
  let store: UsageStore

  @AppStorage(AppPreferences.providerKey(.claudeCode)) private var claudeEnabled = true
  @AppStorage(AppPreferences.providerKey(.codex)) private var codexEnabled = true
  @AppStorage(AppPreferences.providerKey(.ohMyPi)) private var ohMyPiEnabled = true
  @AppStorage(AppPreferences.providerKey(.openCode)) private var openCodeEnabled = true
  @AppStorage(AppPreferences.refreshIntervalKey) private var refreshInterval = 300.0
  @AppStorage(AppPreferences.showMenuBarTotalKey) private var showMenuBarTotal = true
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
    .onChange(of: ohMyPiEnabled) { refreshAfterSettingsChange() }
    .onChange(of: openCodeEnabled) { refreshAfterSettingsChange() }
  }

  private var pageHeader: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("设置")
        .font(.title2.weight(.semibold))
      Text("所有统计都在本机完成，不上传日志或 Token 数据。")
        .foregroundStyle(.secondary)
    }
    .padding(20)
    .frame(maxWidth: .infinity, alignment: .leading)
    .spellbookPanel()
  }

  private var sourceSettings: some View {
    settingsCard("数据源", systemImage: "externaldrive") {
      providerToggle(.claudeCode, isOn: $claudeEnabled)
      providerToggle(.codex, isOn: $codexEnabled)
      providerToggle(.ohMyPi, isOn: $ohMyPiEnabled)
      providerToggle(.openCode, isOn: $openCodeEnabled)
    }
  }

  private var behaviorSettings: some View {
    settingsCard("常驻行为", systemImage: "menubar.rectangle") {
      Toggle("在菜单栏显示今日 Token", isOn: $showMenuBarTotal)
      Toggle(
        "登录时启动",
        isOn: Binding(
          get: { launchAtLogin },
          set: { enabled in updateLaunchAtLogin(enabled) }
        )
      )

      HStack {
        Text("刷新间隔")
        Spacer()
        Picker("刷新间隔", selection: $refreshInterval) {
          Text("1 分钟").tag(60.0)
          Text("5 分钟").tag(300.0)
          Text("15 分钟").tag(900.0)
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
    settingsCard("本地数据", systemImage: "lock.shield") {
      sourcePath("Claude Code", LocalUsageLocations.standard.claudeCodeDirectory)
      sourcePath("Codex", LocalUsageLocations.standard.codexDirectory)
      sourcePath("OpenCode", LocalUsageLocations.standard.openCodeDatabase)
      if let directory = LocalUsageLocations.standard.ohMyPiDirectory {
        sourcePath("Oh My Pi", directory)
      }
    }
  }

  private var diagnostics: some View {
    settingsCard("状态", systemImage: "waveform.path.ecg") {
      HStack {
        if let updated = store.lastUpdated {
          Text("更新于 \(updated, format: .dateTime.hour().minute().second())")
        } else {
          Text("尚未完成首次扫描")
        }
        Spacer()
        Button("立即刷新") { Task { await store.refresh() } }
          .disabled(store.isRefreshing)
      }

      if let diagnostics = store.diagnostics {
        Text(
          "本轮读取 \(diagnostics.filesRead) 个文件 · \(diagnostics.bytesRead.formatted(.byteCount(style: .file))) · \(diagnostics.sourceErrors) 个来源错误"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      HStack {
        Spacer()
        Button("退出 Unsealed Spellbook") {
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
        ? "请在“系统设置 › 通用 › 登录项”中允许此应用。"
        : nil
    } catch {
      launchAtLogin = SMAppService.mainApp.status == .enabled
      launchMessage = error.localizedDescription
    }
  }

  private func abbreviatedPath(_ url: URL) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    return url.path.replacingOccurrences(of: home, with: "~")
  }
}
