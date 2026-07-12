# Repository Guidelines

## Project Structure & Module Organization

This is a SwiftPM macOS menu-bar application targeting macOS 14 or newer. Core collection and aggregation code lives in `Sources/UnsealedSpellbookCore/`; keep it independent of SwiftUI. App entry, observable state, and views live under `Sources/UnsealedSpellbook/{App,Stores,Views}/`; packaging assets live in `Assets/`. Acceptance tests are in `Tests/UnsealedSpellbookCoreTests/`. The project-local app launcher is `script/build_and_run.sh`, and `.codex/environments/environment.toml` wires it to the Codex Run action.

## Build, Test, and Development Commands

- `swift build` compiles the core library and menu-bar executable.
- `swift test` runs all Swift Testing suites.
- `./script/build_and_run.sh --build` creates a signed development `.app` without launching it.
- `./script/build_and_run.sh` builds a development `.app` in `dist/` and launches it.
- `./script/build_and_run.sh --verify` launches the app and confirms its process is running.
- `xcrun swift-format format --in-place --recursive Sources Tests Package.swift` applies the repository formatter.

Use the complete Xcode toolchain if Command Line Tools and the installed SDK differ; the run script selects `/Applications/Xcode.app` automatically.

## Coding Style & Naming Conventions

Use Swift's standard two-space indentation as emitted by `swift-format`. Name types in `UpperCamelCase` and properties, functions, and test methods in `lowerCamelCase`. Keep external-log validation in provider parsers and shared aggregation rules in the core module. Prefer Foundation, SwiftUI, and system SQLite over new dependencies. Do not add a provider abstraction until more than one implementation needs it.

## Testing Guidelines

Tests use Swift Testing (`@Suite`, `@Test`, and `#expect`). Name files `*AcceptanceTests.swift` and describe observable behavior in test titles. Add a failing fixture before changing parser, deduplication, or scanning behavior. Fixtures must contain synthetic usage metadata only—never real prompts, responses, account details, or project paths.

## Commit & Pull Request Guidelines

The repository has no established commit history. Use short imperative subjects such as `Add Codex token parser`. Keep commits focused. Pull requests should explain the behavior change, list verification commands, and include screenshots for menu-bar UI changes.

## Security & Performance

Read only known local log locations. Open OpenCode SQLite in read-only/query-only mode and account for WAL data. Never persist raw conversations. Preserve bounded JSONL reads, incremental offsets, refresh deduplication, and the 512 KiB line ceiling unless tests and profiling justify a change.
