import AppKit
import SwiftUI
import UnsealedSpellbookCore
import UnsealedSpellbookLanguage

enum SpellbookDesign {
  static let windowSize = CGSize(width: 1040, height: 720)
  static let minimumWindowSize = CGSize(width: 840, height: 620)
  static let toolbarHeight: CGFloat = 58
  static let spacing: CGFloat = 12
  static let panelRadius: CGFloat = 14

  static let background = dynamicColor(light: 0xF4F3F8, dark: 0x0F0F14)
  static let surface = dynamicColor(light: 0xFFFFFF, dark: 0x222129)
  static let surfaceSoft = dynamicColor(light: 0xECEEF3, dark: 0x18171F)
  static let line = dynamicColor(
    light: 0x3A3850,
    dark: 0xF0EEFF,
    lightAlpha: 0.16,
    darkAlpha: 0.16
  )
  static let panelShadow = dynamicColor(
    light: 0x25223B,
    dark: 0x000000,
    lightAlpha: 0.08,
    darkAlpha: 0.28
  )
  static let accent = dynamicColor(light: 0x5754C7, dark: 0xA4A1FF)
  static let muted = dynamicColor(light: 0x706E78, dark: 0xAAA8B3)
  static let track = dynamicColor(light: 0xE6E4EC, dark: 0x36343E)
  static let iconBackground = dynamicColor(light: 0xF0EFF5, dark: 0x2C2A34)
  static let segmentedBackground = dynamicColor(
    light: 0x6F6C7B,
    dark: 0x9B97AA,
    lightAlpha: 0.13,
    darkAlpha: 0.18
  )
  static let segmentSelection = dynamicColor(
    light: 0xFFFFFF,
    dark: 0x474451,
    lightAlpha: 0.94,
    darkAlpha: 0.86
  )
  static let success = dynamicColor(light: 0x2F8D55, dark: 0x63C982)
  static let metricBlue = dynamicColor(light: 0x397CCB, dark: 0x72A7E5)
  static let metricPurple = dynamicColor(light: 0x9257C8, dark: 0xC18AE5)
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
    case .openClaude: "OpenClaude"
    case .codex: "Codex"
    case .ohMyPi: "Oh My Pi"
    case .openCode: "OpenCode"
    case .geminiCLI: "Gemini CLI"
    }
  }

  var systemImage: String {
    switch self {
    case .claudeCode: "brain.head.profile"
    case .openClaude: "command.circle"
    case .codex: "terminal"
    case .ohMyPi: "circle.hexagongrid"
    case .openCode: "chevron.left.forwardslash.chevron.right"
    case .geminiCLI: "sparkles"
    }
  }

  var tintColor: Color {
    switch self {
    case .claudeCode: Color(red: 0.85, green: 0.47, blue: 0.34)
    case .openClaude: Color(red: 1, green: 0.48, blue: 0.10)
    case .codex: Color(red: 0.36, green: 0.36, blue: 0.90)
    case .geminiCLI: Color(red: 0.18, green: 0.53, blue: 0.95)
    case .ohMyPi: Color(red: 0.98, green: 0.45, blue: 0.09)
    case .openCode:
      dynamicColor(light: 0x5D5D64, dark: 0xC6C6CC)
    }
  }
}

struct ProviderIcon: View {
  let provider: AIProvider
  let size: CGFloat

  init(_ provider: AIProvider, size: CGFloat = 24) {
    self.provider = provider
    self.size = size
  }

  var body: some View {
    Image(systemName: provider.systemImage)
      .font(.system(size: size * 0.52, weight: .semibold))
      .foregroundStyle(provider.tintColor)
      .frame(width: size, height: size)
      .background(SpellbookDesign.iconBackground)
      .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
      .accessibilityHidden(true)
  }
}

extension ModelIdentity {
  func localizedDisplayName(language: AppLanguage) -> String {
    let localizedName = isKnown ? name : language.text(.unknownModel)
    guard let variant else { return localizedName }
    return "\(localizedName) · \(variant)"
  }
}

extension UsagePeriod {
  func displayName(language: AppLanguage) -> String {
    switch self {
    case .today: language.text(.periodToday)
    case .thisWeek: language.text(.periodThisWeek)
    case .last7Days: language.text(.periodLast7Days)
    case .last30Days: language.text(.periodLast30Days)
    case .thisMonth: language.text(.periodThisMonth)
    }
  }
}

extension BadgeTier {
  func displayName(language: AppLanguage) -> String {
    switch self {
    case .bronze: language.text(.tierBronze)
    case .silver: language.text(.tierSilver)
    case .gold: language.text(.tierGold)
    case .diamond: language.text(.tierDiamond)
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
  func compactTokenCount(language: AppLanguage) -> String {
    formatted(
      .number
        .notation(.compactName)
        .precision(.fractionLength(0...1))
        .locale(language.locale)
    )
  }
}

extension Double {
  func compactUSDCost() -> String {
    let magnitude = abs(self)
    let scales = [1.0, 1_000, 1_000_000, 1_000_000_000, 1_000_000_000_000]
    let suffixes = ["", "K", "M", "B", "T"]
    var unit = scales.lastIndex(where: { magnitude >= $0 }) ?? 0
    var scaled = self / scales[unit]

    func compactFractionDigits(for value: Double) -> Int {
      if abs(value) < 10 { return 2 }
      if abs(value) < 100 { return 1 }
      return 0
    }

    var maximumFractionDigits = unit == 0 ? 2 : compactFractionDigits(for: scaled)
    if unit > 0, unit < scales.count - 1 {
      let roundingScale = pow(10, Double(maximumFractionDigits))
      if (abs(scaled) * roundingScale).rounded() / roundingScale >= 1_000 {
        unit += 1
        scaled = self / scales[unit]
        maximumFractionDigits = compactFractionDigits(for: scaled)
      }
    }

    let fractionLength: ClosedRange<Int>
    if unit == 0 {
      fractionLength = magnitude > 0 && magnitude < 0.01 ? 2...6 : 2...2
    } else {
      fractionLength = 0...maximumFractionDigits
    }
    let number = scaled.formatted(
      .number
        .precision(.fractionLength(fractionLength))
        .locale(Locale(identifier: "en_US"))
    )
    return "$\(number)\(suffixes[unit])"
  }
}

extension Achievement {
  func localizedTitle(language: AppLanguage) -> String {
    language.translation(for: "achievement.\(id).title") ?? title
  }

  func localizedDetail(language: AppLanguage) -> String {
    language.translation(for: "achievement.\(id).detail") ?? detail
  }

  func localizedProgress(language: AppLanguage) -> String {
    switch progressMetric {
    case .count(let current, let target):
      return language.text(
        .achievementCountProgressFormat,
        current.compactTokenCount(language: language),
        target.compactTokenCount(language: language)
      )
    case .cache(let hitRate, let sample):
      return language.text(
        .achievementCacheProgressFormat,
        hitRate.formatted(
          .percent.precision(.fractionLength(0)).locale(language.locale)
        ),
        sample.compactTokenCount(language: language)
      )
    case .unavailable:
      return language.text(.achievementProgressUnavailable)
    }
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
    .shadow(color: SpellbookDesign.panelShadow, radius: 4, y: 1)
  }
}

struct SpellbookPressButtonStyle: ButtonStyle {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .opacity(configuration.isPressed ? 0.72 : 1)
      .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
      .animation(
        reduceMotion ? nil : .easeOut(duration: 0.10),
        value: configuration.isPressed
      )
  }
}

struct SpellbookSegmentedControl<Option: Hashable>: View {
  let options: [Option]
  @Binding var selection: Option
  var horizontalPadding: CGFloat = 14
  let title: (Option) -> String
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Namespace private var selectionIndicator
  @State private var hoveredOption: Option?

  var body: some View {
    HStack(spacing: 0) {
      ForEach(options, id: \.self) { option in
        Button {
          withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 1)) {
            selection = option
          }
        } label: {
          Text(title(option))
            .fontWeight(selection == option ? .semibold : .regular)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, horizontalPadding)
            .frame(minHeight: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(SpellbookPressButtonStyle())
        .foregroundStyle(selection == option ? Color.primary : Color.secondary)
        .background {
          if selection == option {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
              .fill(SpellbookDesign.segmentSelection)
              .shadow(color: SpellbookDesign.panelShadow, radius: 4, y: 1)
              .matchedGeometryEffect(id: "selection", in: selectionIndicator)
          } else if hoveredOption == option {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
              .fill(Color.primary.opacity(0.055))
          }
        }
        .onHover { isHovering in
          hoveredOption = isHovering ? option : (hoveredOption == option ? nil : hoveredOption)
        }
        .accessibilityAddTraits(selection == option ? .isSelected : [])
      }
    }
    .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hoveredOption)
    .padding(3)
    .background(
      SpellbookDesign.segmentedBackground,
      in: RoundedRectangle(cornerRadius: 9, style: .continuous)
    )
  }
}
