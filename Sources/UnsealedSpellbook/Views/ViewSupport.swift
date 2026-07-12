import AppKit
import SwiftUI
import UnsealedSpellbookCore

enum SpellbookDesign {
  static let windowSize = CGSize(width: 1040, height: 720)
  static let toolbarHeight: CGFloat = 58
  static let sidebarWidth: CGFloat = 330
  static let spacing: CGFloat = 12
  static let panelRadius: CGFloat = 14

  static let background = dynamicColor(light: 0xF5F5F7, dark: 0x101014)
  static let surface = dynamicColor(light: 0xFFFFFF, dark: 0x1C1C20)
  static let surfaceSoft = dynamicColor(light: 0xECECEE, dark: 0x141418)
  static let toolbar = dynamicColor(
    light: 0xFAFAFC,
    dark: 0x1E1E22,
    lightAlpha: 0.88,
    darkAlpha: 0.90
  )
  static let line = dynamicColor(
    light: 0x3C3C43,
    dark: 0xEBEBF5,
    lightAlpha: 0.14,
    darkAlpha: 0.14
  )
  static let accent = dynamicColor(light: 0x5856D6, dark: 0x8F8CFF)
  static let muted = dynamicColor(light: 0x6E6E73, dark: 0xA1A1A6)
  static let track = dynamicColor(light: 0xE8E8EB, dark: 0x34343A)
  static let iconBackground = dynamicColor(light: 0xF4F4F6, dark: 0x2A2A30)
  static let segmentedBackground = dynamicColor(
    light: 0x767680,
    dark: 0x767680,
    lightAlpha: 0.16,
    darkAlpha: 0.16
  )
  static let success = dynamicColor(light: 0x28A745, dark: 0x4BD166)
  static let metricBlue = dynamicColor(light: 0x4C8EE8, dark: 0x6EA6F2)
  static let metricPurple = dynamicColor(light: 0xAF52DE, dark: 0xC879EC)
}

private func dynamicColor(
  light: UInt32,
  dark: UInt32,
  lightAlpha: CGFloat = 1,
  darkAlpha: CGFloat = 1
) -> Color {
  let lightColor = nsColor(light, alpha: lightAlpha)
  let darkColor = nsColor(dark, alpha: darkAlpha)
  return Color(
    nsColor: NSColor(name: nil) { appearance in
      appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        ? darkColor : lightColor
    }
  )
}

private func nsColor(_ hex: UInt32, alpha: CGFloat) -> NSColor {
  NSColor(
    red: CGFloat((hex >> 16) & 0xFF) / 255,
    green: CGFloat((hex >> 8) & 0xFF) / 255,
    blue: CGFloat(hex & 0xFF) / 255,
    alpha: alpha
  )
}

extension AIProvider {
  var displayName: String {
    switch self {
    case .claudeCode: "Claude Code"
    case .codex: "Codex"
    case .ohMyPi: "Oh My Pi"
    case .openCode: "OpenCode"
    }
  }

  var systemImage: String {
    switch self {
    case .claudeCode: "brain.head.profile"
    case .codex: "terminal"
    case .ohMyPi: "circle.hexagongrid"
    case .openCode: "chevron.left.forwardslash.chevron.right"
    }
  }

  var tintColor: Color {
    switch self {
    case .claudeCode: Color(red: 1, green: 0.48, blue: 0.10)
    case .codex: SpellbookDesign.accent
    case .ohMyPi: Color(red: 0.12, green: 0.71, blue: 0.65)
    case .openCode: Color(red: 0.09, green: 0.55, blue: 0.82)
    }
  }
}

extension UsagePeriod {
  var displayName: String {
    switch self {
    case .today: "今日"
    case .thisWeek: "本周"
    case .last7Days: "近 7 天"
    case .last30Days: "近 30 天"
    case .thisMonth: "本月"
    }
  }
}

extension BadgeTier {
  var displayName: String {
    switch self {
    case .bronze: "铜"
    case .silver: "银"
    case .gold: "金"
    case .diamond: "钻石"
    }
  }

  var tintColor: Color {
    switch self {
    case .bronze: Color(red: 0.72, green: 0.40, blue: 0.22)
    case .silver: Color(red: 0.63, green: 0.68, blue: 0.75)
    case .gold: Color(red: 0.94, green: 0.66, blue: 0.18)
    case .diamond: .cyan
    }
  }
}

extension Int {
  var compactTokenCount: String {
    formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))
  }
}

extension View {
  func spellbookPanel(radius: CGFloat = SpellbookDesign.panelRadius) -> some View {
    background(
      SpellbookDesign.surface,
      in: RoundedRectangle(cornerRadius: radius, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: radius, style: .continuous)
        .stroke(SpellbookDesign.line, lineWidth: 1)
    }
    .shadow(color: .black.opacity(0.03), radius: 2, y: 1)
  }
}

struct SpellbookSegmentedControl<Option: Hashable>: View {
  let options: [Option]
  @Binding var selection: Option
  var horizontalPadding: CGFloat = 14
  let title: (Option) -> String

  var body: some View {
    HStack(spacing: 0) {
      ForEach(options, id: \.self) { option in
        Button {
          selection = option
        } label: {
          Text(title(option))
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, horizontalPadding)
            .frame(minHeight: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(selection == option ? Color.primary : Color.secondary)
        .background {
          if selection == option {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
              .fill(SpellbookDesign.surface)
              .shadow(color: .black.opacity(0.14), radius: 3, y: 1)
          }
        }
        .accessibilityAddTraits(selection == option ? .isSelected : [])
      }
    }
    .padding(3)
    .background(
      SpellbookDesign.segmentedBackground,
      in: RoundedRectangle(cornerRadius: 9, style: .continuous)
    )
  }
}
