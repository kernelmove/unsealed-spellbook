// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "UnsealedSpellbook",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "UnsealedSpellbookCore", targets: ["UnsealedSpellbookCore"]),
    .executable(name: "UnsealedSpellbook", targets: ["UnsealedSpellbook"]),
  ],
  targets: [
    .target(
      name: "UnsealedSpellbookCore",
      linkerSettings: [.linkedLibrary("sqlite3")]
    ),
    .executableTarget(
      name: "UnsealedSpellbook",
      dependencies: ["UnsealedSpellbookCore"],
      resources: [.copy("Resources/Badges")]
    ),
    .testTarget(
      name: "UnsealedSpellbookCoreTests",
      dependencies: ["UnsealedSpellbookCore", "UnsealedSpellbook"]
    ),
  ]
)
