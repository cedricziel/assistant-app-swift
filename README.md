# Assistant for Apple Platforms

This repository bootstraps a SwiftUI application for iOS 26.3 and macOS 26.3 that wraps the [`cedricziel/assistant`](https://github.com/cedricziel/assistant) stack in a native experience. The project is described with [XcodeGen](https://github.com/yonaskolb/XcodeGen) so the Xcode project can be reproduced at any time.

Key capabilities:

- Shared SwiftUI surface for Cupertino platforms with a single source base under `Sources/Shared`.
- macOS menu bar extra that mirrors the latest conversation for quick replies.
- Chat interface that mirrors the existing web client: threaded history, composer, and assistant responses.
- Multi-account aware data model. Every account is bound to a specific server URL so you can connect to several [`assistant`](https://github.com/cedricziel/assistant) deployments at the same time.
- Login flow that persists account metadata in-memory today and is ready for persistence/back-end wiring.

## Project layout

```
assistant-app-swift/
├── Configurations/            # Per-platform Info.plist templates
├── project.yml                # XcodeGen manifest
├── Resources/Shared/          # Asset catalogs shared across targets
├── Sources/Shared/            # SwiftUI views, models, and stores
└── docs/                      # Architecture notes (e.g., account model diagram)
```

Shared state lives in `AccountStore` and `ChatStore`. `AccountStore` owns authentication state, while `ChatStore` keeps per-account threads and routes outgoing messages through a `ChatService`. `ChatService` now runs a shared agent loop that routes each turn to either local or remote assistant services based on account type.

For a high-level view of the desired remote vs. local account types (including iCloud support), see [`docs/account-model.md`](docs/account-model.md).

## Bootstrapping

1. Make sure XcodeGen is available (`brew install xcodegen`).
2. From this directory run:
   ```sh
   xcodegen generate
   ```
   This produces `Assistant.xcodeproj` locally.
3. Open the project in Xcode (`xed .` or open from Finder) and choose either the **Assistant iOS** or **Assistant macOS** scheme.
4. Select a simulator/device on iOS 26.3 or macOS 26.3 and run.

Whenever you edit `project.yml`, re-run `xcodegen generate` to refresh the Xcode project.

## Pre-commit formatting and linting

This repository includes:

- `opencode.json` formatter rules for Swift and Markdown files.
- `.husky/pre-commit` checks that run before each commit on staged files:
  - Swift: `swiftformat` + `swiftformat --lint`
  - Markdown (`.md`, `.mdx`, `.markdown`): `prettier --write` + `prettier --check`

To enable the repository hook path once per clone:

```sh
git config core.hooksPath .husky
```

Required tooling:

- `swiftformat` (for `.swift` checks)
- one of `bunx`, `npx`, or global `prettier` (for Markdown checks)

## Talking to your servers

- On first launch you will land on the login screen. Enter the base URL of your running [`cedricziel/assistant`](https://github.com/cedricziel/assistant) instance (for example, `https://localhost:3000`), give the profile a friendly display name, and paste the API token issued by the server.
- Each account remembers the server that issued it, so you can add as many as you need. Use the sidebar (or the account toolbar button) to switch between them.
- The macOS menu bar extra mirrors the most recent thread so you can send a quick reply without revealing the full window.
- Remote accounts call the assistant's A2A HTTP interface (`/message/send`) with a Bearer token, so any deployment exposing the [web UI endpoints](https://github.com/cedricziel/assistant/blob/main/docs/web-ui.md) automatically works with the native client.

**Note:** Remote accounts already call the backend through `RemoteAssistantService`. Local account types currently use a placeholder local assistant implementation that echoes input; swap in your on-device model runtime when ready.

## Next steps

- Persist accounts securely (Keychain + on-disk store) so users don't re-enter tokens.
- Replace the `ChatService` stub with real streaming calls to the [`assistant`](https://github.com/cedricziel/assistant) backend.
- Sync conversations by account/server to keep history consistent across devices.
- Flesh out the UI (message metadata, attachments, conversation settings, etc.) once backend capabilities are known.
- Provide production-ready app icons in `Resources/Shared/Assets.xcassets/AppIcon.appiconset`.
