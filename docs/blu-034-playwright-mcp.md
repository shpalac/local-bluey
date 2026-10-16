# BLU-034: Playwright MCP browser boundary

This module is an **experimental, disabled-by-default contract**, not a live
Playwright connection. No browser binary, network client, subprocess, download
directory, credentials or private browsing data are installed or stored.

- `lib/mcp/playwright_browser_adapter.dart` accepts HTTPS URLs matching an
  explicit allowlist (exact hostname or dot-delimited subdomain); local hosts,
  IP literals, alternative ports, credentials, fragments and redirects outside
  the original host are denied. DNS resolution/rebinding and redirect hop
  interception still require enforcement in a future sandboxed transport.
- `McpToolSafetyGate` checks the configured server and requests permission for
  **every** browser action. The only exposed action contracts are navigation
  and text snapshot. Returned text is marked **untrusted** and must never be
  interpreted as an instruction or sent directly into another tool invocation.
- Session generation invalidates late results after cancellation or restart.
  The boundary does not claim to terminate a running browser process.
- No automatic login, form submission, click, uploads, downloads or file write.
  A production transport must separately enforce a restricted filesystem,
  network policy, ephemeral profile, request interception and download denial.
- No WebResearch routing changes: the existing Swift `WebResearch` invokes
  OpenAI web_search and remains a distinct, explicitly configured cloud path.
  Never silently fall back from local browser to WebResearch.
- No user-facing UI is enabled; future opt-in/consent must be accessible,
  RTL-compatible, revocable, logged in ActionLog and represented in the privacy
  data registry. No real-device/macOS permission evidence exists for this slice.

Run reproducible checks with:
```sh
dart format --output=none --set-exit-if-changed lib/mcp/playwright_browser_adapter.dart test/mcp/playwright_browser_adapter_test.dart
flutter analyze
flutter test test/mcp
flutter build bundle --release
```

Rollback: disable or remove the isolated adapter; existing WebResearch and MCP
implementations are unchanged. Acceptance evidence:
`docs/acceptance/temporary/issue-590.json`.

## Pending-approval cancellation fencing (Refs #590)

`BrowserSession` now exposes a volatile invalidation Future for a single
operation generation. Cancel and restart invalidate the pending permission
wait promptly. A later permission grant cannot start an injected transport
because the adapter rechecks its session generation at the invocation
boundary. An already-started transport is not physically aborted; the
caller still receives only a cancelled outcome and no late result.

Run `flutter test test/mcp/playwright_pending_permission_test.dart`.
This is an in-process fake boundary, not a substitute for native browser
process cancellation, DNS rebinding protection or request interception.
