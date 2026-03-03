# Assistant for Apple Platforms

This repository bootstraps a SwiftUI application for iOS 26.3 and macOS 26.3 that wraps the `../assistant` stack in a native experience. The project is described with [XcodeGen](https://github.com/yonaskolb/XcodeGen) so the Xcode project can be reproduced at any time.

Key capabilities:

- Shared SwiftUI surface for Cupertino platforms with a single source base under `Sources/Shared`.
- macOS menu bar extra that mirrors the latest conversation for quick replies.
- Chat interface that mirrors the existing web client: threaded history, composer, and assistant responses.
- Multi-account aware data model. Every account is bound to a specific server URL so you can connect to several `assistant` deployments at the same time.
- Login flow that persists account metadata in-memory today and is ready for persistence/back-end wiring.

## Project layout

```
assistant-app-swift/
├── Configurations/            # Per-platform Info.plist templates
├── project.yml                # XcodeGen manifest
├── Resources/Shared/          # Asset catalogs shared across targets
└── Sources/Shared/            # SwiftUI views, models, and stores
```

Shared state lives in `AccountStore` and `ChatStore`. `AccountStore` owns authentication state, while `ChatStore` keeps per-account threads and routes outgoing messages through a `ChatService`. The current `ChatService` simply echoes text back; swap it out with real calls into the `../assistant` backend when it is ready.

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

## Talking to your servers

- On first launch you will land on the login screen. Enter the base URL of your running `../assistant` instance (for example, `https://localhost:3000`), give the profile a friendly display name, and paste the API token issued by the server.
- Each account remembers the server that issued it, so you can add as many as you need. Use the sidebar (or the account toolbar button) to switch between them.
- The macOS menu bar extra mirrors the most recent thread so you can send a quick reply without revealing the full window.

**Note:** The placeholder `ChatService` only echoes user input. Wire it up to your backend by swapping in a real networking implementation that calls into `../assistant` and updates `ChatStore` with streamed responses.

## Next steps

- Persist accounts securely (Keychain + on-disk store) so users don't re-enter tokens.
- Replace the `ChatService` stub with real streaming calls to the assistant backend.
- Sync conversations by account/server to keep history consistent across devices.
- Flesh out the UI (message metadata, attachments, conversation settings, etc.) once backend capabilities are known.
- Provide production-ready app icons in `Resources/Shared/Assets.xcassets/AppIcon.appiconset`.
