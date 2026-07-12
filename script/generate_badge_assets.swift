#!/usr/bin/env swift
import AppKit
import Foundation

private struct BadgeSpec {
  let id: String
  let systemImage: String
  let tier: String
}

private let fileManager = FileManager.default
private let projectRoot = URL(fileURLWithPath: fileManager.currentDirectoryPath)
private let catalogURL = projectRoot.appendingPathComponent(
  "Sources/UnsealedSpellbookCore/UsageAnalytics.swift")
private let framesDirectory = projectRoot.appendingPathComponent("Assets/BadgeFrames")
private let outputDirectory = projectRoot.appendingPathComponent(
  "Sources/UnsealedSpellbook/Resources/Badges")
private let canvasSize = 256

private func matches(_ pattern: String, in source: String) throws -> [NSTextCheckingResult] {
  let expression = try NSRegularExpression(
    pattern: pattern,
    options: [.dotMatchesLineSeparators]
  )
  return expression.matches(
    in: source,
    range: NSRange(source.startIndex..., in: source)
  )
}

private func capture(
  _ index: Int,
  from match: NSTextCheckingResult,
  in source: String
) -> String {
  guard let range = Range(match.range(at: index), in: source) else { return "" }
  return String(source[range])
}

private func readCatalog() throws -> [BadgeSpec] {
  let source = try String(contentsOf: catalogURL, encoding: .utf8)
  let badgePattern =
    #"(?:achievement|cacheAchievement|comingSoon)\(\s*\"([^\"]+)\"\s*,\s*\"[^\"]*\"\s*,\s*\"[^\"]*\"\s*,\s*\"([^\"]+)\"\s*,\s*\.(bronze|silver|gold|diamond)"#
  var badges = try matches(badgePattern, in: source).map {
    BadgeSpec(
      id: capture(1, from: $0, in: source),
      systemImage: capture(2, from: $0, in: source),
      tier: capture(3, from: $0, in: source)
    )
  }

  let hiddenPattern = #"hidden\(\"([^\"]+)\"\)"#
  badges += try matches(hiddenPattern, in: source).map {
    BadgeSpec(
      id: capture(1, from: $0, in: source),
      systemImage: "diamond",
      tier: "diamond"
    )
  }

  guard badges.count == 60, Set(badges.map(\.id)).count == 60 else {
    throw NSError(
      domain: "BadgeAssetGenerator",
      code: 1,
      userInfo: [NSLocalizedDescriptionKey: "Expected 60 unique badges, found \(badges.count)."]
    )
  }
  return badges
}

private func tint(for tier: String) -> NSColor {
  switch tier {
  case "bronze": NSColor(srgbRed: 0.44, green: 0.24, blue: 0.13, alpha: 1)
  case "silver": NSColor(srgbRed: 0.28, green: 0.33, blue: 0.42, alpha: 1)
  case "gold": NSColor(srgbRed: 0.48, green: 0.30, blue: 0.06, alpha: 1)
  default: NSColor(srgbRed: 0.25, green: 0.29, blue: 0.70, alpha: 1)
  }
}

private func drawSignature(_ value: Int, color: NSColor) {
  for bit in 0..<6 {
    let x = CGFloat(100 + bit * 11)
    let y: CGFloat = 62
    let marker = NSBezierPath()
    marker.move(to: NSPoint(x: x, y: y + 3))
    marker.line(to: NSPoint(x: x + 3, y: y))
    marker.line(to: NSPoint(x: x, y: y - 3))
    marker.line(to: NSPoint(x: x - 3, y: y))
    marker.close()
    color.withAlphaComponent(value & (1 << bit) == 0 ? 0.12 : 0.62).setFill()
    marker.fill()
  }
}

private func draw(
  _ badge: BadgeSpec,
  signature: Int,
  frame: CGImage,
  to destination: URL
) throws {
  guard
    let bitmap = NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: canvasSize,
      pixelsHigh: canvasSize,
      bitsPerSample: 8,
      samplesPerPixel: 4,
      hasAlpha: true,
      isPlanar: false,
      colorSpaceName: .deviceRGB,
      bytesPerRow: 0,
      bitsPerPixel: 0
    ),
    let context = NSGraphicsContext(bitmapImageRep: bitmap)
  else {
    throw NSError(domain: "BadgeAssetGenerator", code: 2)
  }

  let canvas = NSRect(x: 0, y: 0, width: canvasSize, height: canvasSize)
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = context
  context.imageInterpolation = .high
  context.cgContext.setFillColor(NSColor.white.cgColor)
  context.cgContext.fill(canvas)
  context.cgContext.interpolationQuality = .high
  context.cgContext.draw(frame, in: canvas)

  let color = tint(for: badge.tier)
  color.withAlphaComponent(0.08).setFill()
  NSBezierPath(ovalIn: NSRect(x: 75, y: 75, width: 106, height: 106)).fill()

  let pointSize = NSImage.SymbolConfiguration(pointSize: 62, weight: .semibold)
  let palette = NSImage.SymbolConfiguration(paletteColors: [color])
  let symbol = NSImage(systemSymbolName: badge.systemImage, accessibilityDescription: nil)?
    .withSymbolConfiguration(pointSize.applying(palette))
  if let symbol {
    let scale = min(76 / symbol.size.width, 76 / symbol.size.height, 1)
    let size = NSSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
    symbol.draw(
      in: NSRect(
        x: (CGFloat(canvasSize) - size.width) / 2,
        y: (CGFloat(canvasSize) - size.height) / 2,
        width: size.width,
        height: size.height
      ),
      from: .zero,
      operation: .sourceOver,
      fraction: 1
    )
  }
  drawSignature(signature, color: color)
  context.flushGraphics()
  NSGraphicsContext.restoreGraphicsState()

  guard let data = bitmap.representation(using: .png, properties: [:]) else {
    throw NSError(domain: "BadgeAssetGenerator", code: 3)
  }
  try data.write(to: destination, options: .atomic)
}

do {
  let badges = try readCatalog()
  try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

  var frames: [String: CGImage] = [:]
  for tier in ["bronze", "silver", "gold", "diamond"] {
    let frameURL = framesDirectory.appendingPathComponent("\(tier).png")
    guard
      let image = NSImage(contentsOf: frameURL),
      let frame = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    else {
      throw NSError(
        domain: "BadgeAssetGenerator",
        code: 4,
        userInfo: [NSLocalizedDescriptionKey: "Missing frame: \(frameURL.path)"]
      )
    }
    frames[tier] = frame
  }

  for (signature, badge) in badges.sorted(by: { $0.id < $1.id }).enumerated() {
    guard let frame = frames[badge.tier] else { continue }
    try draw(
      badge,
      signature: signature,
      frame: frame,
      to: outputDirectory.appendingPathComponent("\(badge.id).png")
    )
  }
  print("Generated \(badges.count) badge assets in \(outputDirectory.path)")
} catch {
  FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
  exit(1)
}
