# Agent Loop

The app routes every chat turn through a single agent loop so local and remote assistants share one execution model.

## Goals

- Keep one deterministic flow for all account types.
- Route to the correct assistant backend (local vs remote) from account policy.
- Add reliability controls (retry on transient remote failures).
- Keep the loop extensible for future tool calls and streaming.

## Current v1 Flow

Each `sendMessage` call runs this state machine:

1. `planning`
   - Validate input and select backend from `AssistantAccount.AccountType`.
   - `remote` accounts use the HTTP assistant service.
   - `localDevice` and `localICloud` accounts use the local assistant service.
2. `generating`
   - Execute the selected backend for one model response.
3. `acting`
   - Reserved for tool execution; currently no-op in v1.
4. `reflecting`
   - Decide whether to complete, retry, or fail.
   - Remote transient failures (for example, network interruptions or 5xx HTTP) are retried with exponential backoff.
5. `completed` or `failed`

The loop records trace events for each phase to support debugging and future telemetry.
`ChatStore` keeps the latest trace per thread so UI surfaces can inspect routing and retry decisions after each send.

## Routing Rules

- **Remote assistant:** `AssistantAccount.AccountType.remote`
- **Local assistant:** `AssistantAccount.AccountType.localDevice` and `.localICloud`

This keeps account identity as the single source of routing truth.

## Reliability Rules

- `maxAttempts` defaults to `2` (initial attempt + 1 retry).
- Retry is only applied for remote backend failures considered transient:
  - `URLError` transport failures.
  - HTTP 5xx responses from `RemoteAssistantService`.
- Backoff uses exponential delay (`baseDelay * 2^(attempt - 1)`).

## Extensibility

v1 intentionally returns one final `ChatMessage`, but the loop structure is prepared for:

- token streaming,
- tool invocation in the `acting` phase,
- fallback policies between backends,
- persisted run/audit logs.
