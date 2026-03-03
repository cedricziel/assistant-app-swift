# Account Model

Assistant needs to differentiate between accounts that reach out to a hosted backend and accounts that live entirely on device. The diagram below outlines the desired structure.

```mermaid
mindmap
  root((Accounts))
    Remote
      "Connects to user-hosted [`assistant`](https://github.com/cedricziel/assistant)"
      "Per-server credentials (API token, base URL)"
      "Thread history synced via remote backend"
    Local
      iCloud
        "Data stored on device"
        "Synced via iCloud / CloudKit"
        "Shared across user devices"
      "Device-Only"
        "Lives entirely on current device"
        "No iCloud or remote sync"
        "Great for temporary conversations"
```

**Implementation guidance**

- Remote accounts should carry metadata describing the server/environment, token lifetime, and any multi-tenant context so that multiple servers can coexist.
- Local accounts should support two policies:
  - _iCloud_: persist conversations in a CloudKit-backed store to keep devices consistent.
  - _Device-only_: keep data sandboxed locally for users who opt out of sync.
- All account types should surface the same `ChatThread` abstractions so the UI can switch seamlessly between them.
