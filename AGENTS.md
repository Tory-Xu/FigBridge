# Repository Guidelines

## Project Structure & Module Organization
`FigBridge` is a Swift Package Manager repository targeting macOS 12+.

- `Sources/FigBridgeCore`: core domain and services (`Models`, `FigmaService`, `AgentService`, batch storage, generation coordination).
- `Sources/FigBridgeApp`: SwiftUI app shell and MVVM UI (`GeneratePage`, `ViewerPage`, `SettingsPage`, view models, app resources).
- `Tests/FigBridgeTests`: unit and integration-style tests for core logic and app-facing view models.
- `scripts/package-dmg.sh`: release packaging script for architecture-specific DMG artifacts.
- `dist/`: generated release outputs.

Keep business logic in `FigBridgeCore`; keep UI composition and state orchestration in `FigBridgeApp`.

## Build, Test, and Development Commands
- `swift run FigBridge`: run the app locally.
- `swift build`: debug build for quick verification.
- `swift test`: run the full test suite.
- `./scripts/package-dmg.sh arm64`: build and package Apple Silicon DMG.
- `./scripts/package-dmg.sh x86_64`: build and package Intel DMG.

Run commands from repository root.

## Coding Style & Naming Conventions
- Language: Swift 6 (`swiftLanguageModes: [.v6]`), 4-space indentation.
- Types: `UpperCamelCase`; properties/functions: `lowerCamelCase`; enum cases: `lowerCamelCase`.
- File names should match primary type or feature (for example, `GenerationCoordinator.swift`, `SettingsViewModelTests.swift`).
- Follow MVVM boundaries: View code in app target, pure logic and side-effect services in core target.

## Testing Guidelines
- Framework: Swift Testing via `swift test` target.
- Test files end with `Tests.swift`; group by feature/service.
- Add regression tests for parser behavior, batch persistence, generation orchestration, and settings changes.
- Prefer deterministic tests with local fixtures and explicit setup helpers in `TestSupport.swift`.

## Commit & Pull Request Guidelines
- Use concise, scoped commit messages. Existing history includes both conventional prefixes and direct Chinese summaries, e.g. `feat: ...`, `fix(ui): ...`, `修复...`.
- Recommended format: `<type>(optional-scope): summary` (`feat`, `fix`, `refactor`, `test`, `docs`, `chore`).
- PRs should include: purpose, key changes, test evidence (`swift test` output), and screenshots/GIFs for UI-affecting changes.
- Link related issues/tasks and call out any behavior or migration impact.
