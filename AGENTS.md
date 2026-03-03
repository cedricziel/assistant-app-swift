# AGENTS.md

This guide is for coding agents working in `assistant-app-swift`.
It captures the current build/test workflow and style conventions.
Follow this file first, then mirror patterns in nearby code.

## 1) Project overview

- App type: shared SwiftUI app for iOS + macOS.
- Project generator: XcodeGen (`project.yml` -> `Assistant.xcodeproj`).
- Main source root: `Sources/Shared`.
- Targets: `Assistant iOS`, `Assistant macOS`.
- Schemes: `Assistant iOS`, `Assistant macOS`, `Assistant (All)`.
- Current test status: no test target exists yet.
- Current lint/format config files: none (`.swiftlint.yml` and `.swiftformat` not present).

## 2) Setup and project generation

Run from repository root: `/Users/cedricziel/private/code/assistant-app-swift`.

```sh
# Install generator (if needed)
brew install xcodegen

# Generate or refresh project from project.yml
xcodegen generate

# Verify schemes/targets/configurations
xcodebuild -list -project "Assistant.xcodeproj"
```

Notes:

- Re-run `xcodegen generate` after any `project.yml` edit.
- Commit intentional updates to `Assistant.xcodeproj` along with source changes.
- Avoid manual edits to generated project internals unless necessary.

## 3) Build commands

Use explicit destinations in automation to avoid ambiguous device selection.

### Build macOS

```sh
xcodebuild -project "Assistant.xcodeproj" -scheme "Assistant macOS" -configuration Debug -destination 'platform=macOS' build
```

### Build iOS simulator

```sh
xcodebuild -project "Assistant.xcodeproj" -scheme "Assistant iOS" -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16' build
```

### Build all app targets

```sh
xcodebuild -project "Assistant.xcodeproj" -scheme "Assistant (All)" -configuration Debug build
```

## 4) Test commands (including single-test runs)

Current state:

- There is no test target yet, so `xcodebuild test` is currently a no-op for real coverage.

Once tests are added, use these forms:

### Run all tests

```sh
xcodebuild -project "Assistant.xcodeproj" -scheme "Assistant iOS" -destination 'platform=iOS Simulator,name=iPhone 16' test
```

### Run one test class

```sh
xcodebuild -project "Assistant.xcodeproj" -scheme "Assistant iOS" -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:'AssistantTests/AccountStoreTests' test
```

### Run one test method

```sh
xcodebuild -project "Assistant.xcodeproj" -scheme "Assistant iOS" -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:'AssistantTests/AccountStoreTests/testLoginRejectsEmptyToken' test
```

Tip: use `-skip-testing:'Target/Class/testMethod'` to isolate failures quickly.

## 5) Lint and format

Current state:

- No repository-owned lint/format commands exist.
- No `Makefile` exists.
- OpenCode formatter config exists in `opencode.json` for `.swift` and Markdown files.
- A repo hook exists at `.husky/pre-commit` to format + lint staged `.swift`, `.md`, `.mdx`, and `.markdown` files.

Agent policy:

1. Keep edits consistent with current Xcode formatting.
2. If globally available, optional checks are acceptable:

```sh
swiftformat Sources/Shared
swiftlint lint --path Sources/Shared
```

3. Do not add new lint/format dependencies unless asked.
4. Pre-commit behavior:

```sh
# Swift files
swiftformat <file>.swift
swiftformat --lint <file>.swift

# Markdown files (uses bunx, npx, or prettier)
prettier --write <file>.md
prettier --check <file>.md
```

## 6) Style guide for this repo

### Imports

- Import only needed frameworks (`SwiftUI` in views, `Foundation` in models/services/stores).
- Keep imports minimal and remove unused imports.
- One import per line.

### File and type organization

- Prefer one primary type per file.
- Match file names to primary types (`ChatStore.swift`, `LoginView.swift`).
- Keep domain-oriented folders (`App`, `Models`, `Services`, `Stores`, `Support`, `Views`).

### Naming conventions

- Types/protocols/enums: UpperCamelCase.
- Methods/properties: lowerCamelCase.
- Booleans: prefix with `is` or `has`.
- IDs and keyed collections: use explicit nouns (`activeAccountID`, `threadsByAccount`).

### Types and mutability

- Prefer `struct` for data/value models (`Codable`, `Hashable`, `Identifiable`).
- Prefer `final class` for shared mutable state stores.
- Default to `let`; use `var` only for required mutation.
- Use `private(set)` for published read-mostly state when possible.

### Concurrency

- Mark UI-facing stores/session objects `@MainActor`.
- Use `async`/`await` in services and stores.
- Start async actions from views with `Task { ... }`.

### Error handling

- Use domain error enums conforming to `LocalizedError`.
- Provide clear user-facing `errorDescription` messages.
- Validate input early with `guard` and fail fast.
- In stores, catch errors and map into UI state (for example `authenticationError`).

### Formatting and control flow

- Indent with 4 spaces.
- Prefer early-return `guard` for invalid/no-op paths.
- Keep closures focused; extract helpers for repeated logic.
- Use multiline argument formatting with trailing commas where it improves diffs.

### SwiftUI patterns

- Use `@EnvironmentObject` for shared app stores.
- Use local `@State` for view-local ephemeral state.
- Keep business logic in stores/services rather than view bodies.
- Use `#if os(iOS)` / `#if os(macOS)` to preserve platform behavior.
- Include `#Preview` blocks for key screens/components.

### Data and privacy

- Avoid displaying or logging raw API tokens.
- Prefer redacted/token-safe representations in UI.
- Keep account/server identity mapping explicit in models.

## 7) Agent behavior expectations

- Make minimal, focused diffs; avoid unrelated refactors.
- Preserve cross-platform behavior when editing shared UI.
- If you add tests, wire targets/schemes so `xcodebuild test` actually executes them.
- If you add tooling commands, update this file.

## 8) Cursor and Copilot rule files

Checked paths:

- `.cursor/rules/`
- `.cursorrules`
- `.github/copilot-instructions.md`

Current state:

- No Cursor or Copilot rule files were found.
- If these files are added later, update this section and align agent instructions.
